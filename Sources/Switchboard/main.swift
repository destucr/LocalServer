import CoreImage
import SwiftUI
import Foundation
if CommandLine.arguments.contains("--scan") {
    for e in Scanner.scan() {
        print("\(e.port)\t\(e.kind.rawValue)\t\(e.title)\t[\(e.group)]\tpid=\(e.pid.map(String.init) ?? "-")\tup=\(e.uptime ?? "-")\tweb=\(e.web.rawValue)\tlan=\(e.lanExposed)\troot=\(e.restart.map { String($0.rootPid) } ?? "-")\t\(e.command.prefix(80))")
    }
    exit(0)
}
// Debug helper: `Switchboard --tip "text"` shows the tooltip bubble for a few seconds.
if let i = CommandLine.arguments.firstIndex(of: "--tip"), CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        TipWindow.shared.show(CommandLine.arguments[i + 1], delay: 0)
        RunLoop.current.run(until: Date().addingTimeInterval(4))
    }
    exit(0)
}

// Debug helpers: `Switchboard --plan <group>` prints the start order; `--act start-stack <group>` runs it.
func loadKnown() -> [KnownServer] {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Switchboard/state.json")
    struct S: Codable { var known: [String: KnownServer] }
    guard let data = try? Data(contentsOf: url), let st = try? JSONDecoder().decode(S.self, from: data) else { return [] }
    let running = Set(Scanner.scan().map(\.key))
    return st.known.values.filter { !running.contains($0.key) }
}
if let i = CommandLine.arguments.firstIndex(of: "--plan"), CommandLine.arguments.count > i + 1 {
    let stopped = loadKnown()
    let levels = StartPlan.levels(startable: stopped.filter { $0.group == CommandLine.arguments[i + 1] && $0.canStart }, pool: stopped)
    for (n, tier) in levels.enumerated() { print("tier \(n + 1): " + tier.map { "\($0.title) :\($0.port) [\($0.group)]" }.joined(separator: ", ")) }
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--act"), CommandLine.arguments.count > i + 2, CommandLine.arguments[i + 1] == "start-stack" {
    let stopped = loadKnown()
    let levels = StartPlan.levels(startable: stopped.filter { $0.group == CommandLine.arguments[i + 2] && $0.canStart }, pool: stopped)
    print("plan:", StartPlan.describe(levels))
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        let failed = await StartPlan.run(levels) { key, text in if let text { print("  \(key.split(separator: "/").last ?? ""): \(text)") } }
        print(failed.map { "FAILED: \($0.title) :\($0.port)" } ?? "all up")
        sem.signal()
    }
    sem.wait()
    exit(0)
}

// Debug helper: `Switchboard --diagnose-test` runs the "why did it stop?" engine against real processes.
if CommandLine.arguments.contains("--diagnose-test") {
    let tmp = NSTemporaryDirectory() + "sbdiag-\(getpid())"
    try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
    func entry(pid: Int32, exec: String) -> PortEntry {
        PortEntry(id: "t", port: 9999, host: "127.0.0.1", lanExposed: false, kind: .dev, title: "Test", pid: pid, command: exec, projectName: "t",
                  projectPath: nil, group: "t", uptime: nil, container: nil, web: .none, restart: nil)
    }
    func launch(_ exe: String, _ args: [String], log: String? = nil) -> Process {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        if let log { FileManager.default.createFile(atPath: log, contents: nil); let h = FileHandle(forWritingAtPath: log); p.standardOutput = h; p.standardError = h }
        p.terminationHandler = { ExitRegistry.record(pid: $0.processIdentifier, status: $0.terminationStatus, signaled: $0.terminationReason == .uncaughtSignal) }
        try! p.run(); return p
    }
    func show(_ title: String, _ d: Diagnosis) {
        print("== \(title)\n   reason: \(d.reason)"); for f in d.facts { print("   - \(f)") }
        if !d.logLines.isEmpty { print("   log: \(d.logLines.last!)") }
    }

    let killed = launch("/bin/sleep", ["60"]); usleep(200_000); kill(killed.processIdentifier, SIGKILL); killed.waitUntilExit(); usleep(200_000)
    show("kill -9", Diagnose.run(entry: entry(pid: killed.processIdentifier, exec: "/bin/sleep"), byUser: false, logPath: nil, shellPid: nil, takenOverBy: nil))

    let termed = launch("/bin/sleep", ["60"]); usleep(200_000); kill(termed.processIdentifier, SIGTERM); termed.waitUntilExit(); usleep(200_000)
    show("kill (SIGTERM)", Diagnose.run(entry: entry(pid: termed.processIdentifier, exec: "/bin/sleep"), byUser: false, logPath: nil, shellPid: nil, takenOverBy: nil))

    let log1 = tmp + "/a.log"
    let crashed = launch("/bin/sh", ["-c", "echo 'starting'; echo \"Error: Cannot find module 'left-pad'\"; exit 1"], log: log1); crashed.waitUntilExit(); usleep(200_000)
    show("exit 1 with a module error", Diagnose.run(entry: entry(pid: crashed.processIdentifier, exec: "/bin/sh"), byUser: false, logPath: log1, shellPid: nil, takenOverBy: nil))

    let log2 = tmp + "/b.log"
    try? "listening...\nError: listen EADDRINUSE: address already in use :::3000\n".write(toFile: log2, atomically: true, encoding: .utf8)
    show("port clash in the log", Diagnose.run(entry: entry(pid: 1, exec: "node"), byUser: false, logPath: log2, shellPid: nil, takenOverBy: nil))

    let log3 = tmp + "/c.log"
    try? "FATAL ERROR: Reached heap limit Allocation failed - JavaScript heap out of memory\n".write(toFile: log3, atomically: true, encoding: .utf8)
    show("heap out of memory in the log", Diagnose.run(entry: entry(pid: 1, exec: "node"), byUser: false, logPath: log3, shellPid: nil, takenOverBy: nil))

    let reports = tmp + "/reports"; try? FileManager.default.createDirectory(atPath: reports, withIntermediateDirectories: true)
    try? "{\"app_name\":\"node\"}\n{\"pid\":4242,\"exception\":{\"type\":\"EXC_BAD_ACCESS\",\"signal\":\"SIGSEGV\"}}".write(toFile: reports + "/node-2026-10-21-101010.ips", atomically: true, encoding: .utf8)
    show("macOS crash report", Diagnose.run(entry: entry(pid: 4242, exec: "/opt/homebrew/bin/node"), byUser: false, logPath: nil, shellPid: nil, takenOverBy: nil, reportsDir: reports))

    show("you pressed Stop", Diagnose.run(entry: entry(pid: 1, exec: "node"), byUser: true, logPath: nil, shellPid: nil, takenOverBy: nil))
    show("no evidence at all", Diagnose.run(entry: entry(pid: 999999, exec: "node"), byUser: false, logPath: nil, shellPid: nil, takenOverBy: nil))
    try? FileManager.default.removeItem(atPath: tmp)
    exit(0)
}

// Debug helper: `Switchboard --nav-test` checks the arrow-key selection logic.
if CommandLine.arguments.contains("--nav-test") {
    MainActor.assumeIsolated {
        func e(_ port: Int, _ group: String, _ title: String) -> PortEntry {
            PortEntry(id: "\(port)", port: port, host: "127.0.0.1", lanExposed: false, kind: .dev, title: title, pid: 1, command: "", projectName: group,
                      projectPath: "/p/\(group)", group: group, uptime: nil, container: nil, web: .page, restart: nil)
        }
        let stopped = KnownServer(key: "/p/b:4000", port: 4000, title: "Storybook", group: "b", projectPath: "/p/b", start: nil, containerID: nil, lastSeen: Date())
        let s = Store(sample: [e(5173, "a", "Vite"), e(3000, "b", "Next.js"), e(3001, "b", "Node.js")], stopped: [stopped])
        func name(_ k: String?) -> String { k.map { ($0 as NSString).lastPathComponent } ?? "none" }
        print("order:", s.navKeys.map(name).joined(separator: " → "))
        print("start: selected=\(name(s.selectedKey)) active=\(name(s.activeKey))")
        s.moveSelection(1); print("down:  selected=\(name(s.selectedKey)) active=\(name(s.activeKey))")
        s.moveSelection(1); s.moveSelection(1); print("down x2: selected=\(name(s.selectedKey))")
        s.moveSelection(1); s.moveSelection(1); s.moveSelection(1); print("down past the end: selected=\(name(s.selectedKey)) (should stay on the last)")
        s.moveSelection(-1); print("up:    selected=\(name(s.selectedKey))")
        s.setHover("/p/a:5173", true); print("pointer enters Vite: keyboardMode=\(s.keyboardMode) active=\(name(s.activeKey))")
        s.moveSelection(-1); print("up again: keyboardMode=\(s.keyboardMode) active=\(name(s.activeKey))")
        s.clearSelection(); print("esc:   selected=\(name(s.selectedKey)) keyboardMode=\(s.keyboardMode)")
        s.query = "next"; print("filter 'next': order =", s.navKeys.map(name).joined(separator: ", "))
        s.moveSelection(-1); print("up with filter: selected=\(name(s.selectedKey)) (first press from nothing goes to the last match)")
    }
    exit(0)
}

// Debug helper: `Switchboard --stack` prints who talks to whom.
if CommandLine.arguments.contains("--stack") {
    let m = Scanner.stack(entries: Scanner.scan())
    for n in m.nodes { print("node \(n.id)\t\(n.role)\t:\(n.port.map(String.init) ?? "-")\t\(n.title)\t[\(n.project ?? "-")]") }
    for e in m.edges { print("edge \(e.from) -> \(e.to)\tconns=\(e.count)\tconfigured=\(e.configured)\tbroken=\(e.broken)\t\(e.hint ?? "")") }
    print("layers:", m.layers().sorted { $0.key < $1.key }.map { "\($0.key.split(separator: ":").last ?? ""):\($0.value)" }.joined(separator: " "))
    exit(0)
}

// Debug helper: `Switchboard --contrast` prints the extra tint chosen for a few wallpapers.
if CommandLine.arguments.contains("--contrast") { Backdrop.report(); exit(0) }

// Build helper: `Switchboard --icon out.png` draws the app icon.
if let i = CommandLine.arguments.firstIndex(of: "--icon"), CommandLine.arguments.count > i + 1 {
    _ = NSApplication.shared
    try? IconArt.appIcon().representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}

// Debug helper: `Switchboard --act start <port>` starts a remembered (stopped) server from the saved state.
if let i = CommandLine.arguments.firstIndex(of: "--act"), CommandLine.arguments.count > i + 2,
   CommandLine.arguments[i + 1] == "start", let port = Int(CommandLine.arguments[i + 2]) {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Switchboard/state.json")
    struct S: Codable { var known: [String: KnownServer] }
    guard let data = try? Data(contentsOf: url), let st = try? JSONDecoder().decode(S.self, from: data),
          let k = st.known.values.first(where: { $0.port == port }) else { print("nothing remembered for \(port)"); exit(1) }
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        do { try await Actions.start(k); print("start ok") } catch { print("error: \(error.localizedDescription)") }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

// Debug helper: `Switchboard --act kill|restart <port>`
if let i = CommandLine.arguments.firstIndex(of: "--act"), CommandLine.arguments.count > i + 2,
   let port = Int(CommandLine.arguments[i + 2]) {
    let verb = CommandLine.arguments[i + 1]
    guard let e = Scanner.scan().first(where: { $0.port == port }) else { print("no listener on \(port)"); exit(1) }
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        do { if verb == "kill" { try await Actions.kill(e) } else { try await Actions.restart(e) }; print("\(verb) ok") }
        catch { print("error: \(error.localizedDescription)") }
        sem.signal()
    }
    sem.wait()
    if let log = Actions.logFile(for: e) { print("log:", log) }
    exit(0)
}
// Debug helper: `Switchboard --screenshot out.png [dark]` renders the popover with sample data.
if let i = CommandLine.arguments.firstIndex(of: "--screenshot"), CommandLine.arguments.count > i + 1 {
    let outPath = CommandLine.arguments[i + 1]
    let dark = CommandLine.arguments.contains("dark")
    MainActor.assumeIsolated {
        func e(_ port: Int, _ title: String, _ group: String, _ kind: EntryKind = .dev, up: String, web: WebKind = .page,
               lan: Bool = false, ms: Int? = nil, status: Int? = 200) -> PortEntry {
            PortEntry(id: "\(port)", port: port, host: "127.0.0.1", lanExposed: lan, kind: kind, title: title, pid: 1,
                      command: "", projectName: group, projectPath: "/Users/dev/\(group)", group: group, uptime: up,
                      container: nil, web: web, restart: nil, status: ms == nil ? nil : status, ms: ms)
        }
        let list = [
            e(5173, "Vite", "storefront", up: "2h 14m", ms: 8),
            e(3000, "Next.js", "dashboard", up: "41m", ms: 31),
            e(3001, "Node.js", "dashboard", up: "41m", lan: true, ms: 12),
            e(8000, "Laravel", "billing-api", up: "5h 3m", web: .api, ms: 120, status: 500),
            e(5432, "PostgreSQL", "billing-api", .database, up: "3d 2h", web: .none),
            e(6379, "Redis", "billing-api", .database, up: "3d 2h", web: .none),
        ]
        let stoppedServer = KnownServer(key: "/Users/dev/dashboard:4000", port: 4000, title: "Storybook", group: "dashboard",
                                        projectPath: "/Users/dev/dashboard",
                                        start: KnownStart(exec: "/usr/bin/true", argv: [], cwd: "/tmp"), containerID: nil, lastSeen: Date())
        // A sample stack for the map: three front ends call the API, the API uses Postgres and Redis, and a .env points at a port nobody listens on.
        func k(_ group: String, _ port: Int) -> String { "/Users/dev/\(group):\(port)" }
        var nodes = list.map { StackNode(id: $0.key, role: .server, port: $0.port, title: $0.title, project: $0.projectName, status: $0.status, entryID: $0.id) }
        nodes.append(StackNode(id: "client:1", role: .client, port: nil, title: "Queue worker", project: "billing-api", status: nil, entryID: nil))
        nodes.append(StackNode(id: "missing:9200", role: .missing, port: 9200, title: "Nothing here", project: nil, status: nil, entryID: nil))
        func edge(_ f: String, _ t: String, _ n: Int) -> StackEdge { StackEdge(from: f, to: t, count: n, hint: nil, configured: false, broken: false) }
        let sampleStack = StackMap(nodes: nodes, edges: [
            edge(k("storefront", 5173), k("billing-api", 8000), 3), edge(k("dashboard", 3000), k("billing-api", 8000), 2),
            edge(k("dashboard", 3001), k("billing-api", 8000), 1), edge(k("billing-api", 8000), k("billing-api", 5432), 4),
            edge(k("billing-api", 8000), k("billing-api", 6379), 2), edge("client:1", k("billing-api", 5432), 2),
            edge("client:1", k("billing-api", 6379), 1),
            StackEdge(from: k("billing-api", 8000), to: "missing:9200", count: 0, hint: "ELASTIC_PORT in .env", configured: true, broken: true),
        ])
        let docs = KnownServer(key: "/Users/dev/dashboard:4100", port: 4100, title: "Docusaurus", group: "dashboard",
                               projectPath: "/Users/dev/dashboard", start: KnownStart(exec: "/usr/bin/true", argv: [], cwd: "/tmp"), containerID: nil, lastSeen: Date())
        let store = Store(sample: list, stopped: [stoppedServer, docs], names: ["/Users/dev/dashboard:3001": "Admin app"],
                          pinned: [], stack: sampleStack, showMap: CommandLine.arguments.contains("map"))
        _ = NSApplication.shared
        Theme.flat = true
        let look = NSAppearance(named: dark ? .darkAqua : .aqua)
        var size = CGSize.zero

        func render(_ matte: Color) -> CGImage? {
            Theme.matte = matte
            let host = NSHostingView(rootView: RootView().environmentObject(store))
            host.appearance = look
            size = host.fittingSize
            let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            win.appearance = look
            win.contentView = host
            win.setFrameOrigin(NSPoint(x: -4000, y: -4000))
            win.orderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
            host.cacheDisplay(in: host.bounds, to: rep)
            win.orderOut(nil)
            return rep.cgImage
        }
        func rgba(_ cg: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            data.withUnsafeMutableBytes { p in
                CGContext(data: p.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    .draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            }
            return data
        }
        /// Render on white and on black; the difference tells us each pixel's real transparency.
        func transparentContent() -> CGImage? {
            guard let onWhite = render(.white), let onBlack = render(.black) else { return nil }
            let w = rgba(onWhite), k = rgba(onBlack)
            var out = [UInt8](repeating: 0, count: w.count)
            for i in stride(from: 0, to: w.count, by: 4) {
                let d = (Int(w[i]) - Int(k[i]) + Int(w[i + 1]) - Int(k[i + 1]) + Int(w[i + 2]) - Int(k[i + 2])) / 3
                let alpha = max(0, min(255, 255 - d))
                out[i] = min(k[i], UInt8(alpha)); out[i + 1] = min(k[i + 1], UInt8(alpha)); out[i + 2] = min(k[i + 2], UInt8(alpha))
                out[i + 3] = UInt8(alpha)
            }
            let width = onWhite.width, height = onWhite.height
            return out.withUnsafeMutableBytes { p in
                CGContext(data: p.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
            }
        }

        if let content = transparentContent() {
            // Fake what macOS does live: a wallpaper behind, blurred, tinted, then the popover content on top.
            let scale: CGFloat = 2, pad: CGFloat = 56
            let w = size.width + pad * 2, h = size.height + pad * 2
            func bitmap() -> NSBitmapImageRep {
                let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                r.size = NSSize(width: w, height: h)
                return r
            }
            func draw(into r: NSBitmapImageRep, _ body: () -> Void) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: r)
                body()
                NSGraphicsContext.restoreGraphicsState()
            }
            let canvas = NSRect(x: 0, y: 0, width: w, height: h)
            let card = NSRect(x: pad, y: pad, width: size.width, height: size.height)
            let path = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)

            // 1. wallpaper
            let wall = bitmap()
            draw(into: wall) {
                let (c1, c2) = dark
                    ? (NSColor(red: 0.08, green: 0.10, blue: 0.22, alpha: 1), NSColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1))
                    : (NSColor(red: 0.80, green: 0.88, blue: 0.99, alpha: 1), NSColor(red: 0.70, green: 0.76, blue: 0.95, alpha: 1))
                NSGradient(starting: c1, ending: c2)!.draw(in: canvas, angle: -50)
                let blobs: [(CGFloat, CGFloat, CGFloat, NSColor)] = dark
                    ? [(0.15, 0.80, 0.55, NSColor(red: 0.30, green: 0.20, blue: 0.80, alpha: 0.85)),
                       (0.85, 0.25, 0.60, NSColor(red: 0.05, green: 0.55, blue: 0.65, alpha: 0.75)),
                       (0.55, 0.60, 0.40, NSColor(red: 0.75, green: 0.20, blue: 0.55, alpha: 0.45))]
                    : [(0.12, 0.85, 0.55, NSColor(red: 0.98, green: 0.62, blue: 0.80, alpha: 0.90)),
                       (0.88, 0.22, 0.60, NSColor(red: 0.45, green: 0.80, blue: 0.95, alpha: 0.90)),
                       (0.55, 0.55, 0.40, NSColor(red: 0.70, green: 0.60, blue: 0.98, alpha: 0.60))]
                for (x, y, r, c) in blobs {
                    let rad = max(w, h) * r
                    NSGradient(colors: [c, c.withAlphaComponent(0)])!
                        .draw(fromCenter: NSPoint(x: w * x, y: h * y), radius: 0, toCenter: NSPoint(x: w * x, y: h * y), radius: rad, options: [])
                }
            }

            // 2. blurred copy of the wallpaper for the card area
            let out = bitmap()
            draw(into: out) { wall.draw(in: canvas) }
            if let cg = wall.cgImage {
                let blurred = CIImage(cgImage: cg).clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 28 * scale])
                    .cropped(to: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                if let bcg = CIContext().createCGImage(blurred, from: blurred.extent) {
                    draw(into: out) {
                        NSGraphicsContext.saveGraphicsState()
                        let shadow = NSShadow()
                        shadow.shadowBlurRadius = 30
                        shadow.shadowOffset = NSSize(width: 0, height: -12)
                        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.30)
                        shadow.set()
                        NSColor.black.setFill()
                        path.fill()
                        NSGraphicsContext.restoreGraphicsState()

                        NSGraphicsContext.saveGraphicsState()
                        path.addClip()
                        NSImage(cgImage: bcg, size: NSSize(width: w, height: h)).draw(in: canvas)
                        // 3. the material tint, then the content
                        (dark ? NSColor(white: 0.10, alpha: 0.62) : NSColor(white: 1.0, alpha: 0.66)).setFill()
                        NSBezierPath(rect: card).fill()
                        NSImage(cgImage: content, size: size).draw(in: card)
                        NSGraphicsContext.restoreGraphicsState()

                        (dark ? NSColor.white.withAlphaComponent(0.20) : NSColor.white.withAlphaComponent(0.70)).setStroke()
                        path.lineWidth = 0.75
                        path.stroke()
                    }
                }
            }
            try? out.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outPath))
            print("wrote \(outPath)")
        }
    }
    exit(0)
}
Migration.run()
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
