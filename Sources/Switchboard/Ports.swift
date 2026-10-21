import Darwin
import Foundation

enum Ports {
    /// True if nothing holds the port (catches listeners we can't see, e.g. other users' processes).
    static func isFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return true }
        defer { close(fd) }
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = UInt16(port).bigEndian
        a.sin_addr.s_addr = INADDR_ANY
        return withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        } == 0
    }

    static func nextFree(after port: Int, taken: Set<Int>) -> Int {
        var p = port + 1
        while p < 65535, taken.contains(p) || !isFree(p) { p += 1 }
        return p
    }
}
