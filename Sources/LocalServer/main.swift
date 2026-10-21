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
    let out_path = CommandLine.arguments[i + 1]
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
            // Compose the popover as a card with rounded corners and a shadow on a soft backdrop.
            let scale: CGFloat = 2, pad: CGFloat = 44
            let w = size.width + pad * 2, h = size.height + pad * 2
            let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            out.size = NSSize(width: w, height: h)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
            let canvas = NSRect(x: 0, y: 0, width: w, height: h)
            NSGradient(starting: NSColor(red: 0.87, green: 0.91, blue: 0.97, alpha: 1),
                       ending: NSColor(red: 0.78, green: 0.83, blue: 0.93, alpha: 1))!.draw(in: canvas, angle: -50)
            let card = NSRect(x: pad, y: pad, width: size.width, height: size.height)
            let path = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 28
            shadow.shadowOffset = NSSize(width: 0, height: -10)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.set()
            NSColor.white.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            rep.draw(in: card)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.withAlphaComponent(0.12).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
            try? out.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out_path))
            print("wrote \(out_path)")
        }
    }
    exit(0)
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
