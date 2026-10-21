import Foundation
if CommandLine.arguments.contains("--scan") {
    for e in Scanner.scan() {
        print("\(e.port)\t\(e.kind.rawValue)\t\(e.title)\t[\(e.group)]\tpid=\(e.pid.map(String.init) ?? "-")\tup=\(e.uptime ?? "-")\tlan=\(e.lanExposed)\troot=\(e.restart.map { String($0.rootPid) } ?? "-")\t\(e.command.prefix(80))")
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
LocalServerApp.main()
