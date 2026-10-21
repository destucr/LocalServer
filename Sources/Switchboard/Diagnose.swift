import Darwin
import Foundation

/// Why a server stopped, in plain words, with the evidence behind it.
struct Diagnosis {
    var reason: String          // one line, shown on the row and in the notification
    var facts: [String] = []    // the evidence, one line each
    var logLines: [String] = []
    var logPath: String?
    var reportPath: String?
    var at = Date()
}

struct ExitInfo { var status: Int32; var signaled: Bool }

/// How processes that Switchboard launched ended. Only these give an exact exit code or signal.
enum ExitRegistry {
    private static let lock = NSLock()
    private static var map: [Int32: ExitInfo] = [:]
    static func record(pid: Int32, status: Int32, signaled: Bool) { lock.lock(); map[pid] = ExitInfo(status: status, signaled: signaled); lock.unlock() }
    static func info(_ pids: [Int32?]) -> ExitInfo? { lock.lock(); defer { lock.unlock() }; return pids.compactMap { $0 }.compactMap { map[$0] }.first }
}

enum Diagnose {
    static func run(entry: PortEntry, byUser: Bool, logPath: String?, shellPid: Int32?, takenOverBy: PortEntry?,
                    reportsDir: String = NSHomeDirectory() + "/Library/Logs/DiagnosticReports", now: Date = Date()) -> Diagnosis {
        var d = Diagnosis(reason: "", at: now)
        if byUser {
            d.reason = "Stopped by you in Switchboard"
            return d
        }

        // 1. Exact exit status, for servers Switchboard started.
        var exitReason: String?
        if let x = ExitRegistry.info([entry.pid, entry.restart?.rootPid]) {
            let (text, fact) = describe(exit: x)
            exitReason = text
            d.facts.append(fact)
        }

        // 2. A macOS crash report for this process.
        let name = ((entry.restart?.exec ?? entry.command.split(separator: " ").first.map(String.init) ?? "") as NSString).lastPathComponent
        var crashReason: String?
        if let pid = entry.pid, let r = crashReport(pid: pid, name: name, dir: reportsDir, since: now.addingTimeInterval(-900)) {
            crashReason = "Crashed: \(r.summary)"
            d.facts.append("macOS wrote a crash report: \(r.summary)")
            d.reportPath = r.path
        }

        // 3. What the server said last.
        var logReason: String?
        if let path = logPath {
            d.logPath = path
            d.logLines = tail(path, maxLines: 14)
            if let hit = classify(d.logLines) { logReason = hit.reason; d.facts.append("Last output: \(hit.line)") }
        }

        // 4. Someone else took the port, or its terminal went away.
        var takeover: String?
        if let other = takenOverBy {
            takeover = "Replaced: \(other.title) now uses :\(entry.port)"
            d.facts.append("PID \(other.pid.map(String.init) ?? "?") (\(other.title)) is listening on :\(entry.port) now")
        }
        var terminal: String?
        if let sh = shellPid, !Proc.isAlive(sh) {
            terminal = "Its terminal session ended"
            d.facts.append("The shell that started it (PID \(sh)) is gone, so closing the window stops it")
        }

        // Level 2 ("warn") is a normal state on a busy Mac, so only the critical level counts as evidence.
        let pressure = memoryPressure()
        if pressure >= 4 { d.facts.append("Your Mac was critically low on memory around then") }

        d.reason = crashReason ?? logReason ?? exitReason ?? takeover ?? terminal
            ?? (pressure >= 4 ? "Probably killed because your Mac ran out of memory"
                              : "Stopped without an error. Most likely Ctrl+C or a closed terminal")
        if d.facts.isEmpty { d.facts.append("No exit status, crash report or log output was available. Servers started from Switchboard give the most detail") }
        return d
    }

    // MARK: Exit status

    static func signalName(_ n: Int32) -> String {
        [1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 6: "SIGABRT", 9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV", 13: "SIGPIPE", 15: "SIGTERM"][n] ?? "signal \(n)"
    }

    static func describe(exit x: ExitInfo) -> (reason: String, fact: String) {
        if !x.signaled {
            return x.status == 0
                ? ("Exited normally: it finished or shut itself down", "Exit code 0")
                : ("Crashed: it exited with code \(x.status)", "Exit code \(x.status)")
        }
        let sig = signalName(x.status)
        let reason: String
        switch x.status {
        case 9: reason = "Killed (SIGKILL): the system ran out of memory, or someone ran kill -9"
        case 11, 10, 4, 6: reason = "Crashed hard (\(sig))"
        case 15: reason = "Stopped by a signal (SIGTERM), for example kill or a shutdown"
        case 2: reason = "Interrupted with Ctrl+C"
        case 1: reason = "Its terminal was closed (SIGHUP)"
        default: reason = "Ended by \(sig)"
        }
        return (reason, "Ended by \(sig)")
    }

    // MARK: Logs

    static func tail(_ path: String, maxLines: Int) -> [String] {
        guard let h = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 24_000 ? size - 24_000 : 0)
        let text = String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self)
        return Array(text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.suffix(maxLines))
    }

    /// Looks for the usual causes in the last lines of output, newest first.
    static func classify(_ lines: [String]) -> (reason: String, line: String)? {
        let rules: [(String, String)] = [
            (#"EADDRINUSE|address already in use"#, "The port was already in use"),
            (#"heap out of memory|JavaScript heap|ENOMEM|Cannot allocate memory|out of memory"#, "Ran out of memory"),
            (#"Cannot find module|ModuleNotFoundError|No module named"#, "A module is missing"),
            (#"^Killed$|\bKilled\b: 9"#, "Killed, probably because it ran out of memory"),
            (#"Segmentation fault|Bus error|Illegal instruction"#, "Crashed hard (memory error)"),
            (#"Error:|Exception|Traceback|panic:|Fatal|Uncaught"#, "Crashed with an error"),
        ]
        for line in lines.reversed() {
            for (pattern, reason) in rules where line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                let shown = line.count > 120 ? String(line.prefix(117)) + "…" : line
                return (reason == "Crashed with an error" ? "Crashed: \(shown)" : reason, shown)
            }
        }
        return nil
    }

    // MARK: macOS crash reports

    static func crashReport(pid: Int32, name: String, dir: String, since: Date) -> (summary: String, path: String)? {
        guard !name.isEmpty, let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        for f in files where (f.hasSuffix(".ips") || f.hasSuffix(".crash")) && f.lowercased().hasPrefix(name.lowercased()) {
            let path = dir + "/" + f
            guard let m = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date, m > since,
                  let h = FileHandle(forReadingAtPath: path) else { continue }
            let text = String(decoding: (try? h.read(upToCount: 65_536)) ?? Data(), as: UTF8.self)
            try? h.close()
            func first(_ pattern: String) -> String? {
                guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
                let hit = String(text[r])
                return hit.split(whereSeparator: { "\":,[] ".contains($0) }).last.map(String.init)
            }
            let reportPid = first(#""pid"\s*:\s*\d+"#) ?? first(#"Process:\s+\S+\s+\[\d+\]"#).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) }
            guard reportPid == String(pid) else { continue }
            let type = first(#""type"\s*:\s*"EXC_[A-Z_]+""#) ?? first(#"Exception Type:\s*EXC_[A-Z_]+"#) ?? "crash"
            let signal = first(#""signal"\s*:\s*"SIG[A-Z]+""#) ?? first(#"\(SIG[A-Z]+\)"#).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "()")) }
            return ("\(type)\(signal.map { " (\($0))" } ?? "")", path)
        }
        return nil
    }

    // MARK: System

    /// 1 normal, 2 warning (common on a busy Mac), 4 critical.
    static func memoryPressure() -> Int {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 ? Int(level) : 1
    }
}

extension Proc {
    /// The interactive shell above this process (the terminal tab it was started from), if any.
    static func ancestorShell(_ pid: Int32) -> Int32? {
        var cur = pid
        for _ in 0..<10 {
            guard let b = bsd(cur) else { return nil }
            let parent = Int32(b.pbi_ppid)
            guard parent > 1 else { return nil }
            if let path = Proc.path(parent), ["zsh", "bash", "fish", "sh", "tcsh", "nu"].contains((path as NSString).lastPathComponent),
               let a = argsEnv(parent), !a.argv.contains("-c") { return parent }
            cur = parent
        }
        return nil
    }

    /// A log file the process writes to, if its output is redirected to one. Only works while it is alive.
    static func logFile(_ pid: Int32) -> String? {
        for fd: Int32 in [1, 2] { if let p = fdPath(pid, fd: fd), !p.hasPrefix("/dev/") { return p } }
        return nil
    }
}

/// Stops done from the command line. The app reads this so it does not report them as unexpected.
enum ExpectedStops {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Switchboard")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("expected-stops.json")
    }

    private static func read() -> [String: Double] {
        (try? JSONDecoder().decode([String: Double].self, from: Data(contentsOf: url))) ?? [:]
    }

    static func mark(_ keys: [String]) {
        let now = Date().timeIntervalSince1970
        var m = read().filter { now - $0.value < 600 }
        for k in keys { m[k] = now }
        try? JSONEncoder().encode(m).write(to: url, options: .atomic)
    }

    static func contains(_ key: String) -> Bool {
        read()[key].map { Date().timeIntervalSince1970 - $0 < 120 } ?? false
    }
}
