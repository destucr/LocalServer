import Foundation

struct Flavor {
    var name: String
    var kind: EntryKind
    var isWeb: Bool = true
}

struct ProjectInfo {
    var name: String
    var path: String
}

enum Detector {
    // MARK: Project

    private static let markers = [
        "package.json", "composer.json", "Cargo.toml", "go.mod", "pyproject.toml",
        "Gemfile", "mix.exs", "pom.xml", "build.gradle", "deno.json", "docker-compose.yml", "compose.yaml",
    ]

    static func project(cwd: String?) -> ProjectInfo? {
        guard let cwd, cwd != "/" else { return nil }
        let home = NSHomeDirectory()
        guard cwd.hasPrefix(home + "/") || cwd.hasPrefix("/Volumes/") || cwd.hasPrefix("/private/var/www") || cwd.hasPrefix("/var/www") else { return nil }
        let fm = FileManager.default

        var dir = cwd
        var nearest: String?
        var gitRoot: String?
        for _ in 0..<10 {
            if nearest == nil, markers.contains(where: { fm.fileExists(atPath: dir + "/" + $0) }) { nearest = dir }
            if fm.fileExists(atPath: dir + "/.git") { gitRoot = dir; break }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent == home || parent == "/" { break }
            dir = parent
        }
        let root = gitRoot ?? nearest ?? cwd
        guard root != home else { return nil }
        var name = (root as NSString).lastPathComponent
        if let nearest, nearest != root, nearest.hasPrefix(root + "/") {
            name += " › " + nearest.dropFirst(root.count + 1)
        }
        return ProjectInfo(name: name, path: root)
    }

    // MARK: Flavor

    private static let databases: [(String, String)] = [
        ("postgres", "PostgreSQL"), ("mysqld", "MySQL"), ("mariadbd", "MariaDB"), ("mongod", "MongoDB"),
        ("redis-server", "Redis"), ("valkey-server", "Valkey"), ("memcached", "Memcached"),
        ("clickhouse", "ClickHouse"), ("influxd", "InfluxDB"), ("cockroach", "CockroachDB"),
        ("qdrant", "Qdrant"), ("meilisearch", "Meilisearch"), ("minio", "MinIO"),
        ("mailpit", "Mailpit"), ("mailhog", "MailHog"), ("etcd", "etcd"),
    ]

    private static let argRules: [(String, String)] = [
        ("next-server", "Next.js"), ("/next/dist", "Next.js"), (".bin/next", "Next.js"),
        ("vite", "Vite"), ("nuxt", "Nuxt"), ("astro", "Astro"), ("remix", "Remix"),
        ("svelte-kit", "SvelteKit"), ("storybook", "Storybook"), ("react-scripts", "Create React App"),
        ("gatsby", "Gatsby"), ("vue-cli-service", "Vue CLI"), ("@angular", "Angular"), ("ng serve", "Angular"),
        ("docusaurus", "Docusaurus"), ("webpack", "webpack"), ("parcel", "Parcel"),
        ("expo", "Expo"), ("metro", "Metro"),
        ("artisan", "Laravel"), ("manage.py", "Django"),
        ("uvicorn", "Uvicorn"), ("gunicorn", "Gunicorn"), ("flask", "Flask"), ("fastapi", "FastAPI"),
        ("http.server", "Python HTTP server"),
        ("puma", "Rails"), ("config.ru", "Rack"), ("rails", "Rails"),
        ("phx.server", "Phoenix"), ("hugo", "Hugo"), ("jekyll", "Jekyll"),
    ]

    private static let fileRules: [(String, String)] = [
        ("artisan", "Laravel"), ("next.config.js", "Next.js"), ("next.config.mjs", "Next.js"), ("next.config.ts", "Next.js"),
        ("nuxt.config.ts", "Nuxt"), ("astro.config.mjs", "Astro"), ("svelte.config.js", "SvelteKit"),
        ("vite.config.ts", "Vite"), ("vite.config.js", "Vite"), ("vite.config.mjs", "Vite"),
        ("manage.py", "Django"), ("config.ru", "Rails"), ("Cargo.toml", "Rust"), ("go.mod", "Go"),
    ]

    private static let runtimes: [String: String] = [
        "node": "Node.js", "php": "PHP", "python": "Python", "python3": "Python", "ruby": "Ruby",
        "java": "Java", "deno": "Deno", "bun": "Bun", "beam.smp": "Erlang",
    ]

    static func flavor(exec: String, argv: [String], cwd: String?, project: ProjectInfo?) -> Flavor {
        let exeName = (exec as NSString).lastPathComponent.lowercased()
        let line = (argv.joined(separator: " ")).lowercased()

        for (needle, title) in databases where exeName == needle || exeName.hasPrefix(needle + "-") {
            return Flavor(name: title, kind: .database, isWeb: ["MinIO", "Mailpit", "MailHog", "Meilisearch", "Qdrant"].contains(title))
        }
        if exeName == "java", line.contains("elasticsearch") || line.contains("opensearch") {
            return Flavor(name: line.contains("opensearch") ? "OpenSearch" : "Elasticsearch", kind: .database)
        }
        for (needle, title) in argRules where line.contains(needle) {
            return Flavor(name: title, kind: .dev)
        }
        // Project files only disambiguate generic runtimes (`node server.js`); a real binary keeps its own name.
        let runtime = runtimes[exeName] ?? runtimes.first(where: { exeName.hasPrefix($0.key) })?.value
        if runtime != nil {
            for r in [cwd, project?.path].compactMap({ $0 }) {
                for (file, title) in fileRules where FileManager.default.fileExists(atPath: r + "/" + file) {
                    return Flavor(name: title, kind: .dev)
                }
            }
            return Flavor(name: runtime!, kind: .dev)
        }
        let display = (argv.first.map { ($0 as NSString).lastPathComponent } ?? exeName)
        return Flavor(name: display, kind: project == nil ? .other : .dev, isWeb: project != nil)
    }

    /// Apps and system daemons that happen to listen on a port; hidden unless "Show all".
    static func isSystemOrApp(exec: String) -> Bool {
        let prefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/Applications/", "/Library/", NSHomeDirectory() + "/Applications/",
                        NSHomeDirectory() + "/Library/"]
        return prefixes.contains { exec.hasPrefix($0) }
    }
}
