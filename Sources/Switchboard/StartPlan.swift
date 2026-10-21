import Foundation

/// "Start my stack": start stopped servers in dependency order and wait for each tier to accept connections.
enum StartPlan {
    /// Tiers of servers. Everything in a tier can start together; a tier starts once the one before is up.
    /// `pool` is every remembered server, so dependencies from other projects are pulled in when they are stopped too.
    static func levels(startable: [KnownServer], pool: [KnownServer]) -> [[KnownServer]] {
        let byKey = Dictionary(pool.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var targets: [String: KnownServer] = [:]
        func add(_ k: KnownServer) {
            guard targets[k.key] == nil, k.canStart else { return }
            targets[k.key] = k
            for u in k.uses ?? [] { if let d = byKey[u] { add(d) } }   // only stopped ones are in the pool
        }
        startable.forEach(add)

        var remaining = Set(targets.keys)
        var out: [[KnownServer]] = []
        while !remaining.isEmpty {
            let ready = remaining.filter { key in (targets[key]!.uses ?? []).allSatisfy { !remaining.contains($0) } }
            let tier = ready.isEmpty ? remaining : ready    // a cycle: start what is left together
            out.append(tier.compactMap { targets[$0] }.sorted { $0.port < $1.port })
            remaining.subtract(tier)
        }
        return out
    }

    static func describe(_ levels: [[KnownServer]]) -> String {
        levels.map { $0.map { "\($0.title) :\($0.port)" }.joined(separator: " + ") }.joined(separator: " → ")
    }

    /// Runs the plan. `status(key, text)` reports progress per server (nil text clears it). Returns the server that never came up.
    static func run(_ levels: [[KnownServer]], timeout: TimeInterval = 60, status: @escaping @Sendable (String, String?) -> Void) async -> KnownServer? {
        for (i, tier) in levels.enumerated() {
            let waiting = i == 0 ? "" : levels[i - 1].map { "\($0.title) :\($0.port)" }.joined(separator: ", ")
            for later in levels.dropFirst(i + 1).flatMap({ $0 }) { status(later.key, "Waiting…") }
            for k in tier { status(k.key, i == 0 ? "Starting…" : "Starting after \(waiting)…") }

            for k in tier {
                do { try await Actions.start(k) } catch {
                    for t in tier { status(t.key, nil) }
                    return k
                }
            }
            var up = Set<Int>()
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline, up.count < tier.count {
                for k in tier where !up.contains(k.port) {
                    if await Task.detached(operation: { Probe.isListening(k.port) }).value { up.insert(k.port); status(k.key, nil) }
                }
                if up.count < tier.count { try? await Task.sleep(for: .milliseconds(500)) }
            }
            if let missing = tier.first(where: { !up.contains($0.port) }) {
                for t in tier { status(t.key, nil) }
                for later in levels.dropFirst(i + 1).flatMap({ $0 }) { status(later.key, nil) }
                return missing
            }
        }
        return nil
    }
}
