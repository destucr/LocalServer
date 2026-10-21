import Foundation

/// Rewrites the port in a server's command so it can be restarted somewhere else.
/// It edits flags it recognises, then falls back to the PORT variable. It cannot change a port that is hard-coded.
enum PortRewrite {
    struct Result {
        var argv: [String]
        var env: [String: String]
        var viaFlag: Bool
    }

    private static let portFlags: Set<String> = ["--port", "-p", "-P", "--listen", "-l", "--bind", "--http-port", "--server-port"]
    private static let positionalAfter: Set<String> = ["http.server", "runserver", "serve"]
    private static let packageRunners: Set<String> = ["npm", "yarn", "pnpm", "bun", "npx"]

    static func apply(argv: [String], env: [String: String], old: Int, new: Int, cwd: String? = nil) -> Result {
        let o = String(old), n = String(new)
        var a = argv
        var changed = false

        for i in a.indices {
            let t = a[i]
            if t == o, i > 0, portFlags.contains(a[i - 1]) || positionalAfter.contains(a[i - 1]) {
                a[i] = n; changed = true
            } else if let eq = t.firstIndex(of: "="), portFlags.contains(String(t[..<eq])), t.hasSuffix(o),
                      t[t.index(after: eq)...] == o || t.hasSuffix(":" + o) {
                a[i] = String(t.dropLast(o.count)) + n; changed = true
            } else if t.hasSuffix(":" + o), isHostPrefix(String(t.dropLast(o.count + 1))) {
                a[i] = String(t.dropLast(o.count)) + n; changed = true
            }
        }

        // `npm run dev` doesn't name the tool, so read what the script runs.
        let runner = URL(fileURLWithPath: a.first ?? "").lastPathComponent
        let text = (a.joined(separator: " ") + " " + (packageRunners.contains(runner) ? scriptText(a, cwd: cwd) : "")).lowercased()
        if !changed, let flag = flag(for: text) {
            var extra = flag.hasSuffix("=") ? [flag + n] : [flag, n]
            if text.contains("vite") { extra.append("--strictPort") }   // otherwise Vite quietly picks another port
            if runner == "npm", !a.contains("--") { a.append("--") }
            a += extra
            changed = true
        }

        var e = env
        if !changed || e["PORT"] == o { e["PORT"] = n }
        return Result(argv: a, env: e, viaFlag: changed)
    }

    private static func scriptText(_ argv: [String], cwd: String?) -> String {
        guard let cwd, let data = FileManager.default.contents(atPath: cwd + "/package.json"),
              let scripts = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["scripts"] as? [String: String] else { return "" }
        let words = argv.dropFirst().filter { !$0.hasPrefix("-") && $0 != "run" && $0 != "run-script" }
        return words.first.flatMap { scripts[$0] } ?? ""
    }

    private static func isHostPrefix(_ s: String) -> Bool {
        s.allSatisfy { $0.isLetter || $0.isNumber || ".-_[]:".contains($0) }
    }

    /// The port option of common dev servers, matched on the command line.
    private static func flag(for cmd: String) -> String? {
        let longPort = ["vite", "astro", "nuxt", "ng serve", "webpack", "storybook", "vue-cli-service", "uvicorn", "flask", "hugo", "jekyll", "remix"]
        if cmd.contains("artisan") && cmd.contains("serve") { return "--port=" }
        if longPort.contains(where: cmd.contains) { return "--port" }
        if cmd.contains("next") || cmd.contains("rails") { return "-p" }
        return nil
    }
}
