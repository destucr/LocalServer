import Darwin
import Foundation

enum Ports {
    /// True if nothing accepts connections on the port. This asks the same question a browser would.
    /// Binding the port to test it is wrong: it fails for a while after a server stops (TIME_WAIT), which looked like "in use".
    static func isFree(_ port: Int) -> Bool { !Probe.isListening(port) }

    static func nextFree(after port: Int, taken: Set<Int>) -> Int {
        var p = port + 1
        while p < 65535, taken.contains(p) || !isFree(p) { p += 1 }
        return p
    }
}
