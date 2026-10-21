import Foundation

struct DockerPort: Hashable {
    var hostPort: Int
    var loopbackOnly: Bool
}

struct DockerEntry: Hashable {
    var container: DockerContainer
    var ports: [DockerPort]
    var project: String?
    var workdir: String?
}

enum Docker {
    static var binary: String? {
        ["/opt/homebrew/bin/docker", "/usr/local/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker",
         NSHomeDirectory() + "/.orbstack/bin/docker"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func list() -> [DockerEntry] {
        guard let bin = binary else { return [] }
        let fmt = "{{.ID}}|{{.Names}}|{{.Image}}|{{.Ports}}|{{.Label \"com.docker.compose.project\"}}|{{.Label \"com.docker.compose.project.working_dir\"}}|{{.Label \"com.docker.compose.service\"}}"
        let r = runCapture(bin, ["ps", "--format", fmt], timeout: 4)
        guard r.status == 0 else { return [] }
        let portRe = try! NSRegularExpression(pattern: #"(?:([0-9.]+|\[[0-9a-f:]*\]|):)?(\d+)(?:-(\d+))?->\d+(?:-\d+)?/tcp"#)

        return r.out.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "|", maxSplits: 6, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 7 else { return nil }
            var ports: [DockerPort] = []
            for seg in f[3].components(separatedBy: ", ") {
                let ns = seg as NSString
                guard let m = portRe.firstMatch(in: seg, range: NSRange(location: 0, length: ns.length)) else { continue }
                let ip = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ""
                let lo = Int(ns.substring(with: m.range(at: 2)))!
                let hi = m.range(at: 3).location != NSNotFound ? Int(ns.substring(with: m.range(at: 3)))! : lo
                for p in lo...min(hi, lo + 50) { ports.append(DockerPort(hostPort: p, loopbackOnly: ip == "127.0.0.1" || ip == "[::1]")) }
            }
            guard !ports.isEmpty else { return nil }
            return DockerEntry(
                container: DockerContainer(id: f[0], name: f[1], image: f[2], service: f[6].isEmpty ? nil : f[6]),
                ports: ports,
                project: f[4].isEmpty ? nil : f[4],
                workdir: f[5].isEmpty ? nil : f[5])
        }
    }
}
