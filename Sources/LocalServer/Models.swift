import Foundation

enum EntryKind: String {
    case dev, database, docker, other

    var symbol: String {
        switch self {
        case .dev: return "terminal"
        case .database: return "cylinder.split.1x2"
        case .docker: return "shippingbox"
        case .other: return "gearshape"
        }
    }
}

struct DockerContainer: Hashable {
    var id: String
    var name: String
    var image: String
    var service: String?
}

/// Everything needed to bring a process back after killing it.
struct RestartSpec: Hashable {
    var exec: String
    var argv: [String]
    var env: [String: String]
    var cwd: String
    var rootPid: Int32
}

struct PortEntry: Identifiable, Hashable {
    var id: String
    var port: Int
    var host: String
    var lanExposed: Bool
    var kind: EntryKind
    var title: String
    var pid: Int32?
    var command: String
    var projectName: String?
    var projectPath: String?
    var group: String
    var uptime: String?
    var container: DockerContainer?
    var web: WebKind
    var restart: RestartSpec?

    var localURL: URL { URL(string: "\(port == 443 || port == 8443 ? "https" : "http")://localhost:\(port)")! }
}
