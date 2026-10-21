import Foundation

/// The `switchboard` command line: the same engine as the menu bar app, for terminals, scripts and AI agents.
enum CLI {
    static let commands: Set<String> = ["status", "start", "stop", "export", "why", "help", "--help", "-h", "version", "--version"]

    static let help = """
    switchboard: see and control your local servers

    Usage:
      switchboard status [--json]        what is running, by project
      switchboard start [folder]         start a project's stack from its switchboard.json, in dependency order
      switchboard stop [folder]          stop a project's servers, front ends first
      switchboard export [folder] [--force]   write switchboard.json from what Switchboard has seen running
      switchboard why <port>             how a stopped server stopped
      switchboard version

    The folder defaults to the current directory.
    """

    static func run(_ args: [String]) -> Int32 {
        let rest = Array(args.dropFirst())
        switch args[0] {
        case "status": return status(json: rest.contains("--json"))
        case "start": return start(rest.first { !$0.hasPrefix("-") })
        case "stop": return stop(rest.first { !$0.hasPrefix("-") })
        case "export": return export(rest.first { !$0.hasPrefix("-") }, force: rest.contains("--force"))
        case "why": return why(rest.first.flatMap { Int($0) })
        case "version", "--version": print("Switchboard \(appVersion())"); return 0
        default: print(help); return 0
        }
    }

    // MARK: Helpers

    private static func root(for arg: String?) -> String {
        let start = arg.map { ($0 as NSString).expandingTildeInPath } ?? FileManager.default.currentDirectoryPath
        let path = URL(fileURLWithPath: start).standardized.path
        return StackFile.find(from: path) ?? Detector.project(cwd: path)?.path ?? path
    }

    private static func runSync<T>(_ work: @escaping () async -> T) -> T {
        let sem = DispatchSemaphore(value: 0)
        var result: T!
        Task.detached { result = await work(); sem.signal() }
        sem.wait()
        return result
    }

    private static func loadKnown() -> [KnownServer] {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Switchboard/state.json")
        struct S: Codable { var known: [String: KnownServer] }
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(S.self, from: data) else { return [] }
        return Array(s.known.values)
    }

    // MARK: Commands

    private static func status(json: Bool) -> Int32 {
        let entries = Scanner.scan().filter { $0.kind != .other }
        if json {
            let rows = entries.map { e -> [String: Any] in
                var r: [String: Any] = ["port": e.port, "name": e.title, "kind": e.kind.rawValue, "web": e.web.rawValue,
                                        "project": e.projectName ?? NSNull(), "projectPath": e.projectPath ?? NSNull(),
                                        "url": e.address, "lanExposed": e.lanExposed]
                if let p = e.pid { r["pid"] = Int(p) }
                if let u = e.uptime { r["uptime"] = u }
                if let s = e.status { r["httpStatus"] = s }
                if let m = e.ms { r["responseMs"] = m }
                return r
            }
            let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            print(String(decoding: data ?? Data("[]".utf8), as: UTF8.self))
            return 0
        }
        guard !entries.isEmpty else { print("Nothing is listening."); return 0 }
        var lastGroup = ""
        for e in entries {
            if e.group != lastGroup { print((lastGroup.isEmpty ? "" : "\n") + e.group); lastGroup = e.group }
            let health = e.status.map { $0 >= 500 ? "HTTP \($0)" : "\(e.ms ?? 0) ms" } ?? ""
            print("  " + String(e.port).padding(toLength: 6, withPad: " ", startingAt: 0) + e.title.padding(toLength: 16, withPad: " ", startingAt: 0)
                  + ("up " + (e.uptime ?? "?")).padding(toLength: 12, withPad: " ", startingAt: 0) + health)
        }
        return 0
    }

    private static func start(_ arg: String?) -> Int32 {
        let root = root(for: arg)
        guard let file = StackFile.load(root: root) else {
            print("No switchboard.json in \(abbreviateHome(root)). Run `switchboard export` there first."); return 1
        }
        let running = Set(Scanner.scan().map(\.key))
        let stopped = file.servers(root: root).filter { !running.contains($0.key) }
        if stopped.isEmpty { print("Everything in \((root as NSString).lastPathComponent) is already running."); return 0 }
        let startable = stopped.filter(\.canStart)
        for k in stopped where !k.canStart { print("Can't start \(k.title) :\(k.port): the file gives no command or container.") }
        let levels = StartPlan.levels(startable: startable, pool: stopped)
        print("Starting: " + StartPlan.describe(levels))
        let failed = runSync { await StartPlan.run(levels) { key, text in if let text { print("  \(key.split(separator: ":").last ?? ""): \(text)") } } }
        if let f = failed { print("\(f.title) :\(f.port) did not come up within a minute. Nothing after it was started."); return 1 }
        print("Stack is up."); return 0
    }

    private static func stop(_ arg: String?) -> Int32 {
        let root = root(for: arg)
        let all = Scanner.scan()
        let mine = all.filter { $0.projectPath == root && $0.kind != .other }
        guard !mine.isEmpty else { print("Nothing is running in \(abbreviateHome(root))."); return 0 }
        // Front ends first, so nothing is left pointing at a server that just went away.
        let map = Scanner.stack(entries: all)
        let layers = map.layers()
        let ordered = mine.sorted { (layers[$0.key] ?? 0, $0.port) < (layers[$1.key] ?? 0, $1.port) }
        ExpectedStops.mark(ordered.map(\.key))
        var failed = 0
        for e in ordered {
            print("Stopping \(e.title) :\(e.port)")
            do { try runSync { await Result { try await Actions.kill(e) } }.get() } catch { print("  \(error.localizedDescription)"); failed += 1 }
        }
        return failed == 0 ? 0 : 1
    }

    private static func export(_ arg: String?, force: Bool) -> Int32 {
        let root = root(for: arg)
        let path = root + "/" + StackFile.fileName
        if FileManager.default.fileExists(atPath: path), !force { print("\(abbreviateHome(path)) already exists. Use --force to replace it."); return 1 }

        // What the app remembered, plus what is running right now (with live links from the connection map).
        let entries = Scanner.scan()
        let map = Scanner.stack(entries: entries)
        var servers: [String: KnownServer] = Dictionary(loadKnown().map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var containerNames: [String: String] = [:]
        for e in entries where (e.kind == .dev || e.kind == .docker) && e.projectPath == root {
            var k = servers[e.key] ?? KnownServer(key: e.key, port: e.port, title: e.title, group: e.group, projectPath: root, start: nil, containerID: nil, lastSeen: Date())
            k.start = e.restart.map { KnownStart(exec: $0.exec, argv: $0.argv, cwd: $0.cwd) } ?? k.start
            if let c = e.container { k.containerID = c.id; containerNames[c.id] = c.name }
            k.uses = Array(Set((k.uses ?? []) + map.edges.filter { $0.from == e.key && !$0.broken }.map(\.to))).sorted()
            servers[e.key] = k
        }
        let file = StackFile.export(root: root, servers: Array(servers.values), containerNames: containerNames)
        guard !file.services.isEmpty else {
            print("No servers from \(abbreviateHome(root)) were seen running. Start them once, then run this again."); return 1
        }
        do { try file.write(to: root) } catch { print("Could not write the file: \(error.localizedDescription)"); return 1 }
        print("Wrote \(abbreviateHome(path)) with \(file.services.count) service\(file.services.count == 1 ? "" : "s"):")
        for s in file.services { print("  \(s.name) :\(s.port)" + ((s.dependsOn ?? []).isEmpty ? "" : "  needs " + s.dependsOn!.joined(separator: ", "))) }
        print("Commit it so your team gets the same stack.")
        return 0
    }

    private static func why(_ port: Int?) -> Int32 {
        guard let port else { print("Usage: switchboard why <port>"); return 1 }
        if let e = Scanner.scan().first(where: { $0.port == port }) { print(":\(port) is running (\(e.title)). Nothing to explain."); return 0 }
        guard let k = loadKnown().first(where: { $0.port == port }) else { print("Nothing was recorded for :\(port)."); return 1 }
        if let r = k.stopReason {
            let ago = k.stoppedAt.map { " \(formatDuration(Int(Date().timeIntervalSince($0)))) ago" } ?? ""
            print("\(k.title) :\(port) stopped\(ago): \(r)")
        } else { print("\(k.title) :\(port) is not running, and no reason was recorded.") }
        return 0
    }
}

private extension Result where Failure == Error {
    init(_ body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}


/// The CLI runs through a symlink in the Homebrew bin, so Bundle.main can't see the app's Info.plist.
private func appVersion() -> String {
    if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
    let exe = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    let plist = exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
    let info = NSDictionary(contentsOf: plist)
    return info?["CFBundleShortVersionString"] as? String ?? "dev"
}
