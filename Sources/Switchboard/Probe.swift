import Darwin
import Foundation

/// What a listening port answers when asked for `GET /` over plain HTTP.
enum WebKind: String {
    case page   // serves HTML, worth opening in a browser
    case api    // speaks HTTP but not HTML (JSON API, 404 JSON, ...)
    case none   // not HTTP, or not probed (databases)
}

struct ProbeResult {
    var kind: WebKind
    var status: Int?
    var ms: Int?
}

enum Probe {
    private static let lock = NSLock()
    private static var cache: [String: (result: ProbeResult, at: Date)] = [:]

    static func check(pid: Int32?, port: Int, host: String) -> ProbeResult {
        if port == 443 || port == 8443 { return ProbeResult(kind: .page, status: nil, ms: nil) }
        let key = "\(pid ?? 0):\(port)"
        lock.lock(); let hit = cache[key]; lock.unlock()
        if let hit, Date().timeIntervalSince(hit.at) < (hit.result.kind == .none ? 5 : 8) { return hit.result }
        let r = request(port: port, host: host)
        lock.lock(); cache[key] = (r, Date()); lock.unlock()
        return r
    }

    private static func request(port: Int, host: String) -> ProbeResult {
        let order = host.contains("::1") ? [true, false] : [false, true]
        for v6 in order {
            let t0 = DispatchTime.now()
            guard let fd = connectLoopback(port: port, v6: v6) else { continue }
            defer { close(fd) }
            let req = "GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nAccept: text/html,*/*\r\nUser-Agent: Switchboard\r\nConnection: close\r\n\r\n"
            guard send(fd, req, req.utf8.count, 0) > 0 else { return ProbeResult(kind: .none, status: nil, ms: nil) }

            var data = Data()
            var buf = [UInt8](repeating: 0, count: 2048)
            var firstByte: DispatchTime?
            while data.count < 2048 {
                let n = recv(fd, &buf, buf.count, 0)
                if n <= 0 { break }
                if firstByte == nil { firstByte = .now() }
                data.append(buf, count: n)
                if data.count > 12, data.range(of: Data("\r\n\r\n".utf8)) != nil { break }
            }
            let (kind, status) = classify(String(decoding: data, as: UTF8.self))
            let ms = firstByte.map { Int(($0.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000) }
            return ProbeResult(kind: kind, status: status, ms: kind == .none ? nil : ms)
        }
        return ProbeResult(kind: .none, status: nil, ms: nil)
    }

    static func classify(_ response: String) -> (WebKind, Int?) {
        guard response.hasPrefix("HTTP/") else { return (.none, nil) }
        let status = response.split(separator: " ", maxSplits: 2).dropFirst().first.flatMap { Int($0) }
        let lower = response.lowercased()
        let headEnd = lower.range(of: "\r\n\r\n")?.lowerBound ?? lower.endIndex
        let headers = lower[..<headEnd]
        if headers.contains("content-type:") {
            let line = headers.components(separatedBy: "\r\n").first { $0.hasPrefix("content-type:") } ?? ""
            return (line.contains("html") ? .page : .api, status)
        }
        let body = lower[headEnd...].drop { $0.isWhitespace }
        return (body.hasPrefix("<!doctype html") || body.hasPrefix("<html") ? .page : .api, status)
    }

    private static func connectLoopback(port: Int, v6: Bool) -> Int32? {
        let fd = socket(v6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var tv = timeval(tv_sec: 0, tv_usec: 800_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        let rc: Int32
        if v6 {
            var a = sockaddr_in6()
            a.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            a.sin6_family = sa_family_t(AF_INET6)
            a.sin6_port = UInt16(port).bigEndian
            a.sin6_addr = in6addr_loopback
            rc = withUnsafePointer(to: &a) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
            }
        } else {
            var a = sockaddr_in()
            a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            a.sin_family = sa_family_t(AF_INET)
            a.sin_port = UInt16(port).bigEndian
            a.sin_addr.s_addr = inet_addr("127.0.0.1")
            rc = withUnsafePointer(to: &a) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        }
        if rc != 0 { close(fd); return nil }
        return fd
    }
}
