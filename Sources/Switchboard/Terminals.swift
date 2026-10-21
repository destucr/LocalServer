import AppKit

/// Terminal apps Switchboard can hand a log to. Only the ones installed are offered.
struct TerminalApp: Identifiable, Hashable {
    let id: String   // bundle id
    let name: String

    static let all: [TerminalApp] = [
        .init(id: "com.apple.Terminal", name: "Terminal"),
        .init(id: "com.googlecode.iterm2", name: "iTerm"),
        .init(id: "com.mitchellh.ghostty", name: "Ghostty"),
        .init(id: "dev.warp.Warp-Stable", name: "Warp"),
        .init(id: "net.kovidgoyal.kitty", name: "kitty"),
        .init(id: "org.alacritty", name: "Alacritty"),
        .init(id: "com.github.wez.wezterm", name: "WezTerm"),
    ]

    static var installed: [TerminalApp] { all.filter { $0.url != nil } }
    static let fallback = all[0]

    /// The app's own icon, so the button looks like the terminal it opens.
    var icon: NSImage { url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage() }

    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    /// Runs an executable script in this terminal. Returns false if the app could not be started.
    func run(script: URL) -> Bool {
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
