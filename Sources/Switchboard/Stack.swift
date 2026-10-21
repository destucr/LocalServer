import Foundation

/// What kind of thing a server is, so the map can draw it like an architecture diagram.
enum StackType: String, Hashable {
    case web, api, database, cache, search, mail, storage, worker, container, missing, server

    var symbol: String {
        switch self {
        case .web: return "globe"
        case .api: return "curlybraces"
        case .database: return "cylinder.split.1x2.fill"
        case .cache: return "bolt.fill"
        case .search: return "magnifyingglass"
        case .mail: return "envelope.fill"
        case .storage: return "externaldrive.fill"
        case .worker: return "gearshape.2.fill"
        case .container: return "shippingbox.fill"
        case .missing: return "questionmark"
        case .server: return "server.rack"
        }
    }

    var label: String {
        switch self {
        case .web: return "Web app"
        case .api: return "API"
        case .database: return "Database"
        case .cache: return "Cache"
        case .search: return "Search"
        case .mail: return "Mail"
        case .storage: return "Storage"
        case .worker: return "Worker"
        case .container: return "Container"
        case .missing: return "Not running"
        case .server: return "Server"
        }
    }

    static func classify(title: String, web: WebKind, isContainer: Bool, image: String? = nil) -> StackType {
        let t = (title + " " + (image ?? "")).lowercased()
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        if has(["postgres", "mysql", "mariadb", "mongo", "clickhouse", "cockroach", "influx", "sqlite"]) { return .database }
        if has(["redis", "valkey", "memcached"]) { return .cache }
        if has(["elasticsearch", "opensearch", "meilisearch", "typesense", "qdrant"]) { return .search }
        if has(["mailpit", "mailhog", "mailcatcher"]) { return .mail }
        if has(["minio"]) { return .storage }
        if isContainer { return .container }
        switch web {
        case .page: return .web
        case .api: return .api
        case .none: return .server
        }
    }
}

/// The running stack as a graph: who talks to whom.
struct StackNode: Identifiable, Hashable {
    enum Role { case server, client, missing }
    var id: String          // PortEntry.key, "client:<pid>", or "missing:<port>"
    var role: Role
    var port: Int?
    var title: String
    var project: String?
    var status: Int?        // HTTP status of GET /, when known
    var entryID: String?    // PortEntry.id, so the map can act on it
    var type: StackType = .server
}

struct StackEdge: Hashable {
    var from: String
    var to: String
    var count: Int          // open connections right now
    var hint: String?       // where a configured link came from, e.g. "DB_PORT in .env"
    var configured: Bool    // found in .env but no live connection
    var broken: Bool        // configured, and nothing listens there
}

struct StackMap {
    var nodes: [StackNode] = []
    var edges: [StackEdge] = []
    static let empty = StackMap()

    func node(_ id: String) -> StackNode? { nodes.first { $0.id == id } }
    func uses(_ id: String) -> [StackNode] { edges.filter { $0.from == id && !$0.broken }.compactMap { node($0.to) } }
    func usedBy(_ id: String) -> [StackNode] { edges.filter { $0.to == id }.compactMap { node($0.from) } }
    func brokenLinks(_ id: String) -> [StackEdge] { edges.filter { $0.from == id && $0.broken } }

    /// Column for each node: sources on the left, what they depend on to the right. Capped so cycles can't run away.
    func layers() -> [String: Int] {
        var layer: [String: Int] = [:]
        for n in nodes { layer[n.id] = 0 }
        let cap = min(3, max(nodes.count - 1, 0))
        for _ in 0..<max(nodes.count, 1) {
            var changed = false
            for e in edges where layer[e.to] != nil && layer[e.from] != nil {
                let want = min(layer[e.from]! + 1, cap)
                if layer[e.to]! < want { layer[e.to] = want; changed = true }
            }
            if !changed { break }
        }
        return layer
    }
}

extension Scanner {
    private struct Conn { var pid: Int32; var localPort: Int; var remotePort: Int }

    static func stack(entries: [PortEntry]) -> StackMap {
        let servers = entries.filter { $0.kind != .other }
        var byPort: [Int: PortEntry] = [:]
        for e in servers where byPort[e.port] == nil { byPort[e.port] = e }
        let allListening = Set(entries.map(\.port))
        var byPid: [Int32: PortEntry] = [:]
        for e in servers.sorted(by: { $0.port < $1.port }) { if let p = e.pid, byPid[p] == nil { byPid[p] = e } }

        var nodes: [String: StackNode] = [:]
        for e in servers {
            nodes[e.key] = StackNode(id: e.key, role: .server, port: e.port, title: e.title, project: e.projectName, status: e.status, entryID: e.id,
                                     type: StackType.classify(title: e.title, web: e.web, isContainer: e.container != nil, image: e.container?.image))
        }

        var counts: [String: [String: Int]] = [:]   // from → to → n
        var clientCache: [Int32: String?] = [:]

        func nodeKey(forPid pid: Int32) -> String? {
            if let e = byPid[pid] { return e.key }
            if let cached = clientCache[pid] { return cached }
            let d = describe(pid: pid, now: Int(Date().timeIntervalSince1970))
            var key: String?
            if d.kind == .dev, d.projectName != nil {   // a worker or script from one of your projects; not a browser or system app
                key = "client:\(pid)"
                nodes[key!] = StackNode(id: key!, role: .client, port: nil, title: d.title, project: d.projectName, status: nil, entryID: nil, type: .worker)
            }
            clientCache[pid] = key
            return key
        }

        for c in connections() {
            guard !allListening.contains(c.localPort), let target = byPort[c.remotePort], target.pid != c.pid,
                  let from = nodeKey(forPid: c.pid), from != target.key else { continue }
            counts[from, default: [:]][target.key, default: 0] += 1
        }

        var edges: [StackEdge] = []
        for (from, tos) in counts { for (to, n) in tos { edges.append(StackEdge(from: from, to: to, count: n, hint: nil, configured: false, broken: false)) } }

        // What each project's .env says it talks to. Live connections win; the rest show as configured or broken.
        var perProject: [String: [PortEntry]] = [:]
        for e in servers where e.kind == .dev { if let p = e.projectPath { perProject[p, default: []].append(e) } }
        for (path, list) in perProject {
            guard let owner = list.min(by: { $0.port < $1.port }) else { continue }
            let own = Set(list.map(\.port))
            for hint in EnvHints.ports(in: path) where !own.contains(hint.port) {
                if let target = byPort[hint.port] {
                    if !edges.contains(where: { $0.from == owner.key && $0.to == target.key }) && owner.key != target.key {
                        edges.append(StackEdge(from: owner.key, to: target.key, count: 0, hint: hint.label, configured: true, broken: false))
                    }
                } else {
                    let id = "missing:\(hint.port)"
                    nodes[id] = StackNode(id: id, role: .missing, port: hint.port, title: "Nothing here", project: nil, status: nil, entryID: nil, type: .missing)
                    edges.append(StackEdge(from: owner.key, to: id, count: 0, hint: hint.label, configured: true, broken: true))
                }
            }
        }
        return StackMap(nodes: nodes.values.sorted { ($0.project ?? "", $0.port ?? 0) < ($1.project ?? "", $1.port ?? 0) },
                        edges: edges.sorted { ($0.from, $0.to) < ($1.from, $1.to) })
    }

    /// Open TCP connections between local processes, from `lsof`.
    private static func connections() -> [Conn] {
        let r = runCapture("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:ESTABLISHED", "-Fpn"], timeout: 8)
        var out: [Conn] = []
        var pid: Int32 = 0
        func port(_ s: Substring) -> Int? { s.lastIndex(of: ":").flatMap { Int(s[s.index(after: $0)...]) } }
        for line in r.out.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let body = line.dropFirst()
            if tag == "p" { pid = Int32(body) ?? 0 }
            else if tag == "n", pid > 0, let arrow = body.range(of: "->") {
                let remote = body[arrow.upperBound...]
                guard remote.hasPrefix("127.") || remote.hasPrefix("[::1]") || remote.hasPrefix("localhost"),
                      let lp = port(body[..<arrow.lowerBound]), let rp = port(remote) else { continue }
                out.append(Conn(pid: pid, localPort: lp, remotePort: rp))
            }
        }
        return out
    }
}

/// Ports a project's .env files point at, such as DB_PORT=5432 or API_URL=http://localhost:8000.
enum EnvHints {
    static func ports(in projectPath: String) -> [(port: Int, label: String)] {
        let urlRe = try! NSRegularExpression(pattern: #"(?:localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0):(\d{2,5})"#)
        let skip: Set<String> = ["PORT", "APP_PORT", "VITE_PORT", "SERVER_PORT", "DEV_PORT", "NEXT_PUBLIC_PORT"]
        var found: [(Int, String)] = []
        for name in [".env", ".env.local", ".env.development"] {
            guard let text = try? String(contentsOfFile: projectPath + "/" + name, encoding: .utf8) else { continue }
            for raw in text.split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
                let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if key.hasSuffix("_PORT"), !skip.contains(key), let p = Int(value), (80...65535).contains(p) {
                    found.append((p, "\(key) in \(name)"))
                } else if let m = urlRe.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                          let r = Range(m.range(at: 1), in: value), let p = Int(value[r]), !skip.contains(key) {
                    found.append((p, "\(key) in \(name)"))
                }
            }
        }
        var seen = Set<Int>()
        return found.filter { seen.insert($0.0).inserted }.prefix(8).map { (port: $0.0, label: $0.1) }
    }
}
