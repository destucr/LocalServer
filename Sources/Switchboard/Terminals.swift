import AppKit

/// Terminal apps Switchboard can hand a log to. Only the ones installed are offered.
struct TerminalApp: Identifiable, Hashable {
    enum Mux: Hashable { case tmux, zellij }

    let id: String   // bundle id, or "tmux:name" for a running session
    let name: String
    var mux: Mux?
    var session: String?

    static let all: [TerminalApp] = [
        .init(id: "com.apple.Terminal", name: "Terminal"),
        .init(id: "com.googlecode.iterm2", name: "iTerm"),
        .init(id: "com.mitchellh.ghostty", name: "Ghostty"),
        .init(id: "dev.warp.Warp-Stable", name: "Warp"),
        .init(id: "net.kovidgoyal.kitty", name: "kitty"),
        .init(id: "org.alacritty", name: "Alacritty"),
        .init(id: "com.github.wez.wezterm", name: "WezTerm"),
    ]

    static var apps: [TerminalApp] { all.filter { $0.url != nil } }
    static let fallback = all[0]

    /// The app's own icon, so the button looks like the terminal it opens.
    var icon: NSImage {
        if mux != nil { return NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: name) ?? NSImage() }
        return url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()
    }

    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    /// Runs an executable script in this terminal. Returns false if the app could not be started.
    func run(script: URL, title: String = "") -> Bool {
        if let mux, let session { return Multiplexers.run(mux, session: session, script: script, title: title) }
        guard let app = url else { return false }
        let args: [String]
        switch id {
        case "com.mitchellh.ghostty", "org.alacritty": args = ["-na", app.path, "--args", "-e", script.path]
        case "net.kovidgoyal.kitty": args = ["-na", app.path, "--args", script.path]
        case "com.github.wez.wezterm": args = ["-na", app.path, "--args", "start", "--", script.path]
        default: args = ["-a", app.path, script.path]   // Terminal, iTerm and Warp open .command files themselves
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = args
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}

/// Sessions that are already open in tmux or zellij. A log opens as a new window or pane there, so nothing new is created on screen.
enum Multiplexers {
    static func binary(_ name: String) -> String? {
        ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/"].map { $0 + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs tmux and zellij, so it must never be called while a view is being drawn. The Store calls it in the background.
    static func scan() -> [TerminalApp] {
        var out: [TerminalApp] = []
        if let t = binary("tmux") {
            // Only sessions with a window attached, since a log in a detached session would open where nobody looks.
            let r = runCapture(t, ["list-sessions", "-F", "#{session_attached}|#{session_name}"], timeout: 2)
            if r.status == 0 {
                for line in r.out.split(separator: "\n") {
                    let f = line.split(separator: "|", maxSplits: 1).map(String.init)
                    if f.count == 2, f[0] != "0" { out.append(.init(id: "tmux:" + f[1], name: "tmux · " + f[1], mux: .tmux, session: f[1])) }
                }
            }
        }
        if let z = binary("zellij") {
            let r = runCapture(z, ["list-sessions", "--no-formatting"], timeout: 2)
            if r.status == 0 {
                for line in r.out.split(separator: "\n") where !line.contains("EXITED") {
                    if let name = line.split(separator: " ").first.map(String.init) { out.append(.init(id: "zellij:" + name, name: "zellij · " + name, mux: .zellij, session: name)) }
                }
            }
        }
        return out
    }

    static func run(_ mux: TerminalApp.Mux, session: String, script: URL, title: String) -> Bool {
        switch mux {
        case .tmux:
            guard let t = binary("tmux") else { return false }
            let r = runCapture(t, ["new-window", "-t", "=\(session):", "-n", title, script.path], timeout: 3)
            if r.status == 0 { bringForward(tmux: t, session: session) }
            return r.status == 0
        case .zellij:
            guard let z = binary("zellij") else { return false }
            return runCapture(z, ["--session", session, "action", "new-pane", "--name", title, "--", script.path], timeout: 3).status == 0
        }
    }

    /// Finds the app that shows the tmux session by walking up from the attached client, and brings it to the front.
    private static func bringForward(tmux: String, session: String) {
        let r = runCapture(tmux, ["list-clients", "-t", "=\(session)", "-F", "#{client_pid}"], timeout: 2)
        guard var pid = r.out.split(separator: "\n").first.flatMap({ Int32($0) }) else { return }
        for _ in 0..<10 {
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                app.activate(); return
            }
            let up = runCapture("/bin/ps", ["-o", "ppid=", "-p", String(pid)], timeout: 1).out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let next = Int32(up), next > 1 else { return }
            pid = next
        }
    }
}
