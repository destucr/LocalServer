import AppKit
import Foundation

enum ActionError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

enum Actions {
    // MARK: Kill

    static func kill(_ e: PortEntry) async throws {
        if let c = e.container {
            guard let bin = Docker.binary else { throw ActionError.message("docker not found") }
            let r = await Task.detached { runCapture(bin, ["stop", c.id], timeout: 30) }.value
            if r.status != 0 { throw ActionError.message("docker stop failed") }
            return
        }
        guard let pid = e.pid else { return }
        try await terminate(pids: unique([e.restart?.rootPid, pid]))
    }

    private static func unique(_ pids: [Int32?]) -> [Int32] {
        var seen = Set<Int32>()
        return pids.compactMap { $0 }.filter { seen.insert($0).inserted }
    }

    /// SIGTERM, wait up to 3s, then SIGKILL stragglers.
    static func terminate(pids: [Int32]) async throws {
        for pid in pids where Proc.isAlive(pid) {
            if Darwin.kill(pid, SIGTERM) != 0 && errno == EPERM {
                throw ActionError.message("Not permitted to stop PID \(pid) (owned by another user)")
            }
        }
        for _ in 0..<30 {
            if pids.allSatisfy({ !Proc.isAlive($0) }) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        for pid in pids where Proc.isAlive(pid) { Darwin.kill(pid, SIGKILL) }
        try? await Task.sleep(for: .milliseconds(200))
    }

    // MARK: Restart

    static func restart(_ e: PortEntry) async throws {
        if let c = e.container {
            guard let bin = Docker.binary else { throw ActionError.message("docker not found") }
            let r = await Task.detached { runCapture(bin, ["restart", c.id], timeout: 60) }.value
            if r.status != 0 { throw ActionError.message("docker restart failed") }
            return
        }
        guard let spec = e.restart, let pid = e.pid else { throw ActionError.message("Nothing to restart") }
        try await terminate(pids: unique([spec.rootPid, pid]))

        let log = try openLog(e.group, e.port, label: "restarted")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: spec.exec)
        p.arguments = Array(spec.argv.dropFirst())
        p.environment = spec.env
        p.currentDirectoryURL = URL(fileURLWithPath: spec.cwd)
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = log
        p.standardError = log
        do { try p.run() } catch { throw ActionError.message("Launch failed: \(error.localizedDescription)") }
    }

    /// One log file per server, appended to. A restarted or started server writes here, so Logs can follow it.
    private static func openLog(_ name: String, _ port: Int, label: String) throws -> FileHandle {
        let dir = NSHomeDirectory() + "/Library/Logs/LocalServer"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let path = "\(dir)/\(slug)-\(port).log"
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        guard let log = FileHandle(forWritingAtPath: path) else { throw ActionError.message("Cannot open the log file") }
        log.seekToEndOfFile()
        log.write(Data("\n--- \(label) \(Date()) ---\n".utf8))
        return log
    }

    // MARK: Start (a server that is not running)

    static func start(_ k: KnownServer) async throws {
        if let id = k.containerID {
            guard let bin = Docker.binary else { throw ActionError.message("docker not found") }
            let r = await Task.detached { runCapture(bin, ["start", id], timeout: 30) }.value
            if r.status != 0 { throw ActionError.message("docker start failed. Was the container removed?") }
            return
        }
        guard let s = k.start else { throw ActionError.message("LocalServer doesn't know how this was started") }
        guard FileManager.default.fileExists(atPath: s.cwd) else { throw ActionError.message("The folder is gone: \(abbreviateHome(s.cwd))") }
        let log = try openLog(k.group, k.port, label: "started")
        let cmd = ([s.exec] + s.argv.dropFirst()).map(shellQuote).joined(separator: " ")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lic", "cd \(shellQuote(s.cwd)) && exec \(cmd)"]   // login shell so nvm, pyenv, etc. are on PATH
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = log
        p.standardError = log
        do { try p.run() } catch { throw ActionError.message("Launch failed: \(error.localizedDescription)") }
    }

    // MARK: Tail

    static func tail(_ e: PortEntry) throws {
        let title = "\(e.title) :\(e.port)"
        if let c = e.container {
            guard let bin = Docker.binary else { throw ActionError.message("docker not found") }
            openTerminal(title: title, command: "\(shellQuote(bin)) logs -f --tail 200 \(shellQuote(c.id))")
            return
        }
        guard let path = logFile(for: e) else {
            throw ActionError.message("No log file found. Restart from here and output will be captured.")
        }
        openTerminal(title: title, command: "tail -n 200 -F \(shellQuote(path))")
    }

    /// stdout/stderr redirected to a file → that file; otherwise the newest log in the project.
    static func logFile(for e: PortEntry) -> String? {
        if let pid = e.pid {
            for fd: Int32 in [1, 2] {
                if let p = Proc.fdPath(pid, fd: fd), !p.hasPrefix("/dev/") { return p }
            }
        }
        guard let root = e.projectPath else { return nil }
        let fm = FileManager.default
        let dirs = ["storage/logs", "log", "logs", "tmp", "."]
        var best: (String, Date)?
        for d in dirs {
            let dir = root + "/" + d
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for n in names where n.hasSuffix(".log") {
                let p = dir + "/" + n
                guard let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date,
                      m > Date().addingTimeInterval(-7 * 86400) else { continue }
                if best == nil || m > best!.1 { best = (p, m) }
            }
        }
        return best?.0
    }

    private static func openTerminal(title: String, command: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("localserver-\(UUID().uuidString.prefix(8)).command")
        let script = "#!/bin/zsh\nprintf '\\033]0;%s\\007' \(shellQuote(title))\nexec \(command)\n"
        try? script.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }

    // MARK: Share

    static func lanAddress() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var fallback: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  ifa.ifa_flags & UInt32(IFF_UP) != 0, ifa.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            let name = String(cString: ifa.ifa_name)
            if name == "en0" { return ip }
            if name.hasPrefix("en") { fallback = fallback ?? ip }
        }
        return fallback
    }

    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
