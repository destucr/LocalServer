import Foundation

@MainActor
final class Tunnel: ObservableObject, Identifiable {
    enum State { case starting, running(String), failed(String) }
    let port: Int
    let provider: String
    @Published var state: State = .starting
    fileprivate var process: Process?
    nonisolated var id: Int { port }

    init(port: Int, provider: String) { self.port = port; self.provider = provider }

    var url: String? { if case .running(let u) = state { return u }; return nil }
}

@MainActor
final class TunnelManager: ObservableObject {
    @Published private(set) var tunnels: [Int: Tunnel] = [:]

    static var provider: (name: String, path: String)? {
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
        for name in ["cloudflared", "ngrok"] {
            if let d = dirs.first(where: { FileManager.default.isExecutableFile(atPath: "\($0)/\(name)") }) { return (name, "\(d)/\(name)") }
        }
        return nil
    }

    func start(port: Int) throws {
        guard let prov = Self.provider else {
            throw ActionError.message("Install a tunnel tool first: brew install cloudflared")
        }
        stop(port: port)
        let t = Tunnel(port: port, provider: prov.name)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: prov.path)
        p.arguments = prov.name == "cloudflared"
            ? ["tunnel", "--no-autoupdate", "--url", "http://localhost:\(port)"]
            : ["http", "\(port)", "--log=stdout", "--log-format=logfmt"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let re = try! NSRegularExpression(pattern: prov.name == "cloudflared"
            ? #"https://[a-z0-9-]+\.trycloudflare\.com"# : #"url=(https://\S+)"#)

        pipe.fileHandleForReading.readabilityHandler = { [weak t] h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            guard !s.isEmpty, let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return }
            let r = Range(m.range(at: m.numberOfRanges > 1 ? 1 : 0), in: s)!
            let url = String(s[r])
            Task { @MainActor in if case .starting = t?.state { t?.state = .running(url); Actions.copy(url) } }
        }
        p.terminationHandler = { [weak self, weak t] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let t, self?.tunnels[t.port] === t else { return }
                if t.url == nil { t.state = .failed("exit \(proc.terminationStatus)") }
                self?.tunnels[t.port] = nil
            }
        }
        try p.run()
        t.process = p
        tunnels[port] = t
    }

    func stop(port: Int) {
        guard let t = tunnels.removeValue(forKey: port) else { return }
        t.process?.terminationHandler = nil
        t.process?.terminate()
    }

    func stopAll() { for p in Array(tunnels.keys) { stop(port: p) } }
}
