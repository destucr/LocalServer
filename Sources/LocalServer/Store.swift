import AppKit
import ServiceManagement
import SwiftUI

/// Everything worth remembering between launches. No environment variables, so no secrets.
private struct SavedState: Codable {
    var known: [String: KnownServer] = [:]
    var names: [String: String] = [:]
    var pinned: Set<String> = []
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var entries: [PortEntry] = []
    @Published private(set) var stopped: [KnownServer] = []
    @Published var query = ""
    @Published var showAll = false
    @Published var message: String?
    @Published var busy: [String: String] = [:]   // row key → what it is doing, e.g. "Restarting…"
    @Published var copiedID: String?
    @Published private(set) var hoverKey: String?
    @Published private(set) var backdropTint: Double = 0.12   // extra tint so text stays readable over the wallpaper
    @Published private(set) var tip: String?   // what the hovered icon does, shown in the footer
    @Published private(set) var recent: Set<String> = []   // servers that just appeared
    private var knownRunningKeys: Set<String>?
    @Published var armedKill: String?
    @Published private(set) var names: [String: String] = [:]
    @Published private(set) var pinned: Set<String> = []
    @Published var showStopped: Bool { didSet { UserDefaults.standard.set(showStopped, forKey: "showStopped") } }
    @Published var notifyOnStop: Bool {
        didSet { UserDefaults.standard.set(notifyOnStop, forKey: "notifyOnStop"); if notifyOnStop { Notifier.requestPermission() } }
    }

    static let shared = Store()
    let tunnels = TunnelManager()

    private var known: [String: KnownServer] = [:]
    private var dirty = false
    private var lastSave = Date()
    private let persistent: Bool
    private var messageTask: Task<Void, Never>?

    // Crash detection
    private var watching: [String: PortEntry] = [:]
    private var missing: [String: Int] = [:]
    private var expectedStops: [String: Date] = [:]

    /// Fixed sample data, no polling, no disk. Used for README screenshots.
    init(sample: [PortEntry], stopped: [KnownServer] = [], names: [String: String] = [:], pinned: Set<String> = []) {
        persistent = false
        showStopped = true
        notifyOnStop = false
        entries = sample
        self.stopped = stopped
        self.names = names
        self.pinned = pinned
    }

    init() {
        persistent = true
        let d = UserDefaults.standard
        showStopped = d.bool(forKey: "showStopped")
        notifyOnStop = d.object(forKey: "notifyOnStop") as? Bool ?? true
        load()
        if notifyOnStop { Notifier.requestPermission() }

        Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self, tunnels] _ in
            MainActor.assumeIsolated { tunnels.stopAll(); self?.persist(force: true) }
        }
    }

    // MARK: Derived lists

    var portQuery: Int? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, q.count <= 5, let n = Int(q), n > 0, n < 65536 else { return nil }
        return n
    }

    var visible: [PortEntry] {
        entries.filter { e in
            (showAll || e.kind != .other || portQuery == e.port) && matches(query, [displayName(e), e.title, e.group, e.command, String(e.port)])
        }
    }

    private func matches(_ q: String, _ fields: [String]) -> Bool {
        q.isEmpty || fields.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    var count: Int { entries.filter { $0.kind != .other }.count }

    var groups: [ProjectGroup] {
        let running = visible
        let runningGroups = Set(running.map { pinned.contains($0.key) ? "Pinned" : $0.group })
        let stoppedVisible = stopped.filter { k in
            matches(query, [k.title, k.group, String(k.port)]) &&
            (showStopped || runningGroups.contains(pinned.contains(k.key) ? "Pinned" : k.group))
        }

        var order: [String] = []
        var run: [String: [PortEntry]] = [:]
        var stop: [String: [KnownServer]] = [:]
        func name(_ key: String, _ group: String) -> String { pinned.contains(key) ? "Pinned" : group }

        for e in running { let g = name(e.key, e.group); if run[g] == nil { order.append(g) }; run[g, default: []].append(e) }
        for k in stoppedVisible { let g = name(k.key, k.group); if run[g] == nil && stop[g] == nil { order.append(g) }; stop[g, default: []].append(k) }

        order.sort { a, b in
            if a == "Pinned" { return true }
            if b == "Pinned" { return false }
            return false   // keep the scan's project order
        }
        return order.map { g in
            let path = g == "Pinned" ? nil : (run[g]?.first?.projectPath ?? stop[g]?.first?.projectPath)
            return ProjectGroup(name: g, path: path, running: run[g] ?? [], stopped: stop[g] ?? [])
        }
    }

    func displayName(_ e: PortEntry) -> String { names[e.key] ?? e.title }
    func isRenamed(_ e: PortEntry) -> Bool { names[e.key] != nil }
    func isPinned(_ key: String) -> Bool { pinned.contains(key) }

    // MARK: Refresh

    func refresh() async {
        let result = await Task.detached(priority: .utility) { Scanner.scan() }.value
        if result != entries { withAnimation(Motion.anim) { entries = result } }
        guard persistent else { return }
        markNew(result)
        remember(result)
        detectStops(result)
        persist()
    }

    /// Rows that show up after the first scan get a short green highlight.
    private func markNew(_ list: [PortEntry]) {
        let keys = Set(list.filter { $0.kind != .other }.map(\.key))
        defer { knownRunningKeys = keys }
        guard let before = knownRunningKeys else { return }
        let fresh = keys.subtracting(before)
        guard !fresh.isEmpty else { return }
        recent.formUnion(fresh)
        Task { try? await Task.sleep(for: .seconds(2)); withAnimation(Motion.anim) { recent.subtract(fresh) } }
    }

    private func remember(_ list: [PortEntry]) {
        let now = Date()
        let runningKeys = Set(list.map(\.key))

        for e in list where e.kind == .dev || e.kind == .docker {
            let k = KnownServer(key: e.key, port: e.port, title: e.title, group: e.group, projectPath: e.projectPath,
                                start: e.restart.map { KnownStart(exec: $0.exec, argv: $0.argv, cwd: $0.cwd) },
                                containerID: e.container?.id, lastSeen: now)
            var old = known[e.key]
            old?.lastSeen = now
            if old != k { dirty = true }
            known[e.key] = k

            // Same server came back on another port (Vite does this): drop the old grey row.
            for (ok, o) in known where ok != e.key && !runningKeys.contains(ok) && o.title == e.title
                && o.projectPath == e.projectPath && o.start?.cwd == k.start?.cwd && k.start != nil {
                known[ok] = nil; dirty = true
            }
        }
        let cutoff = now.addingTimeInterval(-14 * 86400)
        for (k, v) in known where v.lastSeen < cutoff { known[k] = nil; dirty = true }

        let s = known.values.filter { !runningKeys.contains($0.key) }
            .sorted { ($0.group.lowercased(), $0.port) < ($1.group.lowercased(), $1.port) }
        if s != stopped { stopped = s }
    }

    /// A server that was listening and is gone for two scans in a row, without us stopping it.
    private func detectStops(_ list: [PortEntry]) {
        let now = Set(list.filter { $0.kind != .other }.map(\.key))
        for k in now { missing[k] = nil }
        for (k, e) in Array(watching) where !now.contains(k) {
            let n = (missing[k] ?? 0) + 1
            if n >= 2 {
                watching[k] = nil; missing[k] = nil
                let expected = expectedStops[k].map { Date().timeIntervalSince($0) < 120 } ?? false
                if notifyOnStop, !expected {
                    Notifier.post(title: "\(names[k] ?? e.title) stopped", body: "Port \(e.port) in \(e.group) is no longer listening.")
                }
            } else { missing[k] = n }
        }
        for e in list where e.kind != .other { watching[e.key] = e }
    }

    // MARK: Persistence

    private var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalServer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL), let s = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        known = s.known; names = s.names; pinned = s.pinned
    }

    private func persist(force: Bool = false) {
        guard persistent, dirty || force, force || Date().timeIntervalSince(lastSave) > 2 else { return }
        dirty = false; lastSave = Date()
        if let data = try? JSONEncoder().encode(SavedState(known: known, names: names, pinned: pinned)) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    // MARK: Messages

    func flash(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.message = nil }
        }
    }

    /// Called each time the popover opens: read the wallpaper under it and set the tint that keeps text readable.
    func refreshBackdrop(screen: NSScreen?, dark: Bool) {
        let t = Backdrop.tint(screen: screen, dark: dark)
        if abs(t - backdropTint) > 0.005 { backdropTint = t }
    }

    // MARK: Hover and shortcuts

    func setHover(_ key: String, _ on: Bool) {
        if on { hoverKey = key } else if hoverKey == key { hoverKey = nil }
    }

    func setTip(_ text: String?) { if tip != text { tip = text } }

    /// Shown in the footer while the pointer is on a row.
    var hoverHint: String? {
        guard let key = hoverKey else { return nil }
        if let e = entries.first(where: { $0.key == key }) {
            return e.web == .page ? "⌘O Open · ⌘C Copy · ⌘R Restart · ⌘L Logs · ⌘⌫ Stop"
                                  : "⌘C Copy · ⌘R Restart · ⌘L Logs · ⌘⌫ Stop"
        }
        return stopped.contains { $0.key == key } ? "⌘R Start · ⌘⌫ Forget" : nil
    }

    /// ⌘ shortcuts act on the row under the pointer. Returns true if one was handled.
    func shortcut(_ ch: String, deleteKey: Bool) -> Bool {
        guard let key = hoverKey else { return false }
        if let e = entries.first(where: { $0.key == key }) {
            if deleteKey { kill(e); return true }
            switch ch {
            case "o": e.web == .none ? copyLocal(e) : open(e)
            case "c": copyLocal(e)
            case "r": if e.container != nil || e.restart != nil { restart(e) } else { flash("LocalServer can't restart this one. It doesn't know how it was started.") }
            case "l": tail(e)
            case "p": togglePin(e)
            default: return false
            }
            return true
        }
        if let k = stopped.first(where: { $0.key == key }) {
            if deleteKey { forget(k); return true }
            switch ch {
            case "r", "s": if k.canStart { start(k) }
            case "p": togglePin(k)
            default: return false
            }
            return true
        }
        return false
    }

    // MARK: Row actions

    func open(_ e: PortEntry) { NSWorkspace.shared.open(e.localURL) }

    /// What Return does in the filter box: open pages, copy everything else.
    func primary(_ e: PortEntry) { e.web == .page ? open(e) : copyLocal(e) }

    func kill(_ e: PortEntry) {
        if e.kind == .database || e.kind == .other || e.container != nil, armedKill != e.id {
            armedKill = e.id
            Task { try? await Task.sleep(for: .seconds(3)); if armedKill == e.id { armedKill = nil } }
            return
        }
        armedKill = nil
        expectedStops[e.key] = Date()
        perform(e.key, label: "Stopping…", success: "Stopped :\(e.port). Press Start to bring it back.") { try await Actions.kill(e) }
    }

    func restart(_ e: PortEntry) {
        expectedStops[e.key] = Date()
        perform(e.key, label: "Restarting…",
                success: e.container == nil ? "Restarted :\(e.port). Its output is saved in ~/Library/Logs/LocalServer, so Logs works now." : "Restarted :\(e.port)") {
            try await Actions.restart(e)
        }
    }

    func start(_ k: KnownServer) {
        perform(k.key, label: "Starting…", success: "Starting \(k.title) on :\(k.port). It can take a few seconds to show up.", settle: 2.0) {
            try await Actions.start(k)
        }
    }

    func forget(_ k: KnownServer) { known[k.key] = nil; stopped.removeAll { $0.key == k.key }; dirty = true; persist(force: true) }

    func tail(_ e: PortEntry) {
        do { try Actions.tail(e) } catch { flash(error.localizedDescription) }
    }

    private func perform(_ key: String, label: String, success: String, settle: Double = 0.6, _ work: @escaping () async throws -> Void) {
        busy[key] = label
        Task {
            do { try await work(); flash(success) } catch { flash(error.localizedDescription) }
            try? await Task.sleep(for: .seconds(settle))
            await refresh()
            busy[key] = nil
        }
    }

    // MARK: Copy and share

    func copyLocal(_ e: PortEntry) {
        Actions.copy(e.address)
        flash("Copied \(e.address)")
        markCopied(e.id)
    }

    func markCopied(_ id: String) {
        copiedID = id
        Task { try? await Task.sleep(for: .seconds(1.6)); if copiedID == id { copiedID = nil } }
    }

    func copyLAN(_ e: PortEntry) {
        guard let ip = Actions.lanAddress() else { flash("No network address found"); return }
        let url = "http://\(ip):\(e.port)"
        Actions.copy(url)
        flash(e.lanExposed ? "Copied \(url). Anyone on your Wi-Fi can open it." : "Copied \(url), but this server only listens on localhost, so other devices can't reach it.")
    }

    func showQR(_ e: PortEntry) {
        guard let ip = Actions.lanAddress() else { flash("No network address found. Connect to Wi-Fi first."); return }
        let url = "http://\(ip):\(e.port)"
        let note = e.lanExposed
            ? "Scan with your phone's camera. The phone must be on the same Wi-Fi."
            : "Heads up: this server only listens on localhost, so a phone can't reach it yet. Start it with a host option, for example --host 0.0.0.0."
        if Dialogs.qr(title: "Open \(displayName(e)) on your phone", url: url, note: note) { Actions.copy(url); flash("Copied \(url)") }
    }

    func toggleTunnel(_ e: PortEntry) {
        if tunnels.tunnels[e.port] != nil { tunnels.stop(port: e.port); return }
        do { try tunnels.start(port: e.port); flash("Starting a public link. It is copied as soon as it is ready.") } catch { flash(error.localizedDescription) }
    }

    // MARK: Names and pins

    func togglePin(_ e: PortEntry) { setPinned(e.key, !pinned.contains(e.key)) }
    func togglePin(_ k: KnownServer) { setPinned(k.key, !pinned.contains(k.key)) }

    private func setPinned(_ key: String, _ on: Bool) {
        if on { pinned.insert(key) } else { pinned.remove(key) }
        dirty = true; persist(force: true)
    }

    func rename(_ e: PortEntry) {
        guard let new = Dialogs.prompt("Rename :\(e.port)", "Leave empty to go back to “\(e.title)”.", value: names[e.key] ?? "") else { return }
        names[e.key] = new.isEmpty ? nil : new
        dirty = true; persist(force: true)
    }

    // MARK: Whole project

    func stopAll(_ g: ProjectGroup) {
        let targets = g.running.filter { $0.kind != .other }
        guard !targets.isEmpty,
              Dialogs.confirm("Stop \(targets.count) server\(targets.count == 1 ? "" : "s") in \(g.name)?",
                              targets.map { "\(displayName($0)) :\($0.port)" }.joined(separator: "\n"), ok: "Stop all") else { return }
        flash("Stopping \(targets.count) server\(targets.count == 1 ? "" : "s")…")
        for e in targets { expectedStops[e.key] = Date(); busy[e.key] = "Stopping…" }
        Task {
            var failed = 0
            for e in targets { do { try await Actions.kill(e) } catch { failed += 1 } }
            try? await Task.sleep(for: .milliseconds(600))
            await refresh()
            for e in targets { busy[e.key] = nil }
            flash(failed == 0 ? "Stopped everything in \(g.name)." : "\(failed) server\(failed == 1 ? "" : "s") could not be stopped.")
        }
    }

    func restartAll(_ g: ProjectGroup) {
        let targets = g.running.filter { $0.container != nil || $0.restart != nil }
        guard !targets.isEmpty else { flash("Nothing here can be restarted."); return }
        flash("Restarting \(targets.count) server\(targets.count == 1 ? "" : "s")…")
        for e in targets { expectedStops[e.key] = Date(); busy[e.key] = "Restarting…" }
        Task {
            for e in targets { try? await Actions.restart(e) }
            try? await Task.sleep(for: .seconds(1))
            await refresh()
            for e in targets { busy[e.key] = nil }
            flash("Restarted everything in \(g.name).")
        }
    }

    func startAll(_ g: ProjectGroup) {
        let targets = g.stopped.filter(\.canStart)
        guard !targets.isEmpty else { return }
        for k in targets { start(k) }
    }

    func openProject(_ path: String, in app: URL) { Editors.open(path, with: app) }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { flash("Launch at login needs the app in /Applications (./build.sh install)") }
            objectWillChange.send()
        }
    }
}
