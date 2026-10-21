import SwiftUI
import Foundation
if CommandLine.arguments.contains("--scan") {
    for e in Scanner.scan() {
        print("\(e.port)\t\(e.kind.rawValue)\t\(e.title)\t[\(e.group)]\tpid=\(e.pid.map(String.init) ?? "-")\tup=\(e.uptime ?? "-")\tweb=\(e.web.rawValue)\tlan=\(e.lanExposed)\troot=\(e.restart.map { String($0.rootPid) } ?? "-")\t\(e.command.prefix(80))")
    }
    exit(0)
}
// Debug helper: `LocalServer --act kill|restart <port>`
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
// Debug helper: `LocalServer --screenshot out.png` renders the popover with sample data.
if let i = CommandLine.arguments.firstIndex(of: "--screenshot"), CommandLine.arguments.count > i + 1 {
    let out = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated {
        func e(_ port: Int, _ title: String, _ group: String, _ kind: EntryKind = .dev, up: String, web: WebKind = .page, lan: Bool = false) -> PortEntry {
            PortEntry(id: "\(port)", port: port, host: "127.0.0.1", lanExposed: lan, kind: kind, title: title, pid: 1,
                      command: "", projectName: group, projectPath: "/Users/dev/\(group)", group: group, uptime: up,
                      container: nil, web: web, restart: nil)
        }
        let store = Store(sample: [
            e(5173, "Vite", "storefront", up: "2h 14m"), e(3000, "Next.js", "dashboard", up: "41m"),
            e(3001, "Node.js", "dashboard", up: "41m", lan: true),
            e(8000, "Laravel", "billing-api", up: "5h 3m", web: .api), e(5432, "PostgreSQL", "billing-api", .database, up: "3d 2h", web: .none),
            e(6379, "Redis", "billing-api", .database, up: "3d 2h", web: .none),
            e(8025, "mailpit", "Docker", .docker, up: "1d 4h"),
        ])
        _ = NSApplication.shared
        let host = NSHostingView(rootView: RootView().environmentObject(store))
        let size = host.fittingSize
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .aqua)
        host.appearance = NSAppearance(named: .aqua)
        win.contentView = host
        win.backgroundColor = .windowBackgroundColor
        win.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        win.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
            print("wrote \(out) \(size)")
        }
    }
    exit(0)
}
LocalServerApp.main()
