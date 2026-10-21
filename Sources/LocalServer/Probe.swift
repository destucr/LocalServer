import Darwin
import Foundation

/// What a listening port answers when asked for `GET /` over plain HTTP.
enum WebKind: String {
    case page   // serves HTML — worth opening in a browser
    case api    // speaks HTTP but not HTML (JSON API, 404 JSON, …)
    case none   // not HTTP, or not probed (databases)
}

enum Probe {
    private static let lock = NSLock()
    private static var cache: [String: (kind: WebKind, at: Date)] = [:]

    static func kind(pid: Int32?, port: Int, host: String) -> WebKind {
        if port == 443 || port == 8443 { return .page }
        let key = "\(pid ?? 0):\(port)"
        lock.lock(); let hit = cache[key]; lock.unlock()
        if let hit, Date().timeIntervalSince(hit.at) < (hit.kind == .none ? 5 : 60) { return hit.kind }
        let k = request(port: port, host: host)
        lock.lock(); cache[key] = (k, Date()); lock.unlock()
        return k
    }

    private static func request(port: Int, host: String) -> WebKind {
        let order = host.contains("::1") ? [true, false] : [false, true]
        for v6 in order {
            guard let fd = connectLoopback(port: port, v6: v6) else { continue }
            defer { close(fd) }
            let req = "GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nAccept: text/html,*/*\r\nUser-Agent: LocalServer\r\nConnection: close\r\n\r\n"
            guard send(fd, req, req.utf8.count, 0) > 0 else { return .none }

            var data = Data()
            var buf = [UInt8](repeating: 0, count: 2048)
            while data.count < 2048 {
                let n = recv(fd, &buf, buf.count, 0)
                if n <= 0 { break }
                data.append(buf, count: n)
                if data.count > 12, data.range(of: Data("\r\n\r\n".utf8)) != nil { break }
            }
            return classify(String(decoding: data, as: UTF8.self))
        }
        return .none
    }

    static func classify(_ response: String) -> WebKind {
        guard response.hasPrefix("HTTP/") else { return .none }
        let lower = response.lowercased()
        let headEnd = lower.range(of: "\r\n\r\n")?.lowerBound ?? lower.endIndex
        let headers = lower[..<headEnd]
        if headers.contains("content-type:") {
            let line = headers.components(separatedBy: "\r\n").first { $0.hasPrefix("content-type:") } ?? ""
            return line.contains("html") ? .page : .api
        }
        let body = lower[headEnd...].drop { $0.isWhitespace }
        return body.hasPrefix("<!doctype html") || body.hasPrefix("<html") ? .page : .api
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
