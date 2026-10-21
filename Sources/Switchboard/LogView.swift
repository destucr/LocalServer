import SwiftUI

/// Where a server's output comes from.
enum LogSource: Equatable {
    case file(String)
    case docker(bin: String, id: String)
}

struct LogLine: Identifiable {
    enum Kind { case plain, error, warn, marker }
    let id: Int
    let text: String
    let kind: Kind
}

/// Follows a log file, or `docker logs -f`, and keeps the last few thousand lines.
@MainActor
final class LogTail: ObservableObject {
    let source: LogSource
    let title: String
    let key: String
    @Published private(set) var lines: [LogLine] = []
    @Published private(set) var note: String?   // why nothing is coming in, when there is a reason
    @Published var query = ""
    @Published var follow = true

    private static let cap = 3000
    private static let maxLine = 4000
    private var nextID = 0
    private var offset: UInt64 = 0
    private var timer: Timer?
    private var process: Process?
    private var pending = Data()   // bytes after the last newline, so a line or a multibyte character is never cut in two
    private var midLine = false   // the offset may sit inside a line, so the first partial line is dropped

    init(source: LogSource, title: String, key: String) {
        self.source = source
        self.title = title
        self.key = key
    }

    var shown: [LogLine] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? lines : lines.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    var text: String { shown.map(\.text).joined(separator: "\n") }

    /// Shown under the toolbar, so you can see which file the lines come from.
    var origin: String {
        switch source {
        case .file(let p): return abbreviateHome(p)
        case .docker(_, let id): return "docker container \(id.prefix(12))"
        }
    }

    func clear() { lines = [] }

    // MARK: Following

    func start() {
        guard timer == nil, process == nil else { return }
        switch source {
        case .file(let path):
            if lines.isEmpty { offset = Self.startOffset(path); midLine = offset > 0; pending = Data() }
            readFile(path)
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.readFile(path) }
            }
        case .docker(let bin, let id):
            lines = []
            pending = Data()
            note = nil
            let p = Process()
            let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["logs", "-f", "--tail", "200", id]
            p.standardOutput = pipe
            p.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                let data = h.availableData
                if data.isEmpty { h.readabilityHandler = nil; return }
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.append(data) } }
            }
            p.terminationHandler = { [weak self, weak p] proc in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, let p, self.process === p else { return }   // ignore the exit we caused by stopping
                        self.note = proc.terminationStatus == 0 ? "The container stopped, so there is nothing more to follow." : "docker logs ended (exit \(proc.terminationStatus)). Is Docker still running?"
                    }
                }
            }
            do { try p.run(); process = p } catch { note = "Could not run docker: \(error.localizedDescription)" }
        }
    }

    /// Stops reading. A file picks up where it left off on the next start.
    func stop() {
        timer?.invalidate()
        timer = nil
        if let p = process {
            process = nil
            (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if p.isRunning { p.terminate() }
        }
    }

    /// The last ~64 KB. The first partial line is dropped.
    private static func startOffset(_ path: String) -> UInt64 {
        let size = ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.uint64Value ?? 0
        return size > 65_536 ? size - 65_536 : 0
    }

    private func readFile(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            note = "The log file is gone. It may have been deleted or rotated. It is shown again if it comes back."
            return
        }
        guard let h = FileHandle(forReadingAtPath: path) else {
            note = "Switchboard can't read this file (permission denied)."
            return
        }
        defer { try? h.close() }
        note = nil
        let size = (try? h.seekToEnd()) ?? 0
        if size < offset {   // truncated or replaced
            offset = 0
            pending = Data()
            append(Data("--- the file was reset, reading from the top ---\n".utf8))
        }
        guard size > offset else { return }
        // After a long pause, skip to the recent end instead of replaying everything.
        if size - offset > 262_144 { offset = size - 65_536; pending = Data(); midLine = true }
        try? h.seek(toOffset: offset)
        guard var data = try? h.read(upToCount: 524_288), !data.isEmpty else { return }
        offset += UInt64(data.count)
        if midLine {
            midLine = false
            if let nl = data.firstIndex(of: 0x0A) { data = data.suffix(from: data.index(after: nl)) } else { return }
        }
        append(data)
    }

    private func append(_ chunk: Data) {
        pending.append(chunk)
        guard let last = pending.lastIndex(of: 0x0A) else {
            if pending.count > 1_000_000 { pending = Data() }   // a single endless line, give up on it
            return
        }
        let complete = pending[pending.startIndex..<last]
        pending = Data(pending[pending.index(after: last)...])
        var out = lines
        for raw in String(decoding: complete, as: UTF8.self).components(separatedBy: "\n") {
            var t = Self.clean(raw)
            if t.count > Self.maxLine { t = String(t.prefix(Self.maxLine)) + " … (line cut)" }
            out.append(LogLine(id: nextID, text: t, kind: Self.kind(t)))
            nextID += 1
        }
        if out.count > Self.cap { out.removeFirst(out.count - Self.cap) }
        lines = out
    }

    private static let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")

    private static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\r", with: "")
        if t.contains("\u{1B}") { t = ansi.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "") }
        return t
    }

    private static func kind(_ t: String) -> LogLine.Kind {
        if t.hasPrefix("--- ") { return .marker }
        let l = t.lowercased()
        if l.contains("error") || l.contains("exception") || l.contains("fatal") || l.contains("failed") || l.contains("traceback") { return .error }
        if l.contains("warn") { return .warn }
        return .plain
    }
}

/// The log screen. It replaces the list, so there is no second window to manage.
struct LogView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var tail: LogTail
    private var running: Bool { store.entries.contains { $0.key == tail.key } }

    var body: some View {
        VStack(spacing: 0) {
            bar
            Divider()
            HStack(spacing: 6) {
                Text(tail.note ?? tail.origin).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(tail.note == nil ? Color.secondary : Brand.orange)
                if !running && tail.note == nil { Text("· stopped").foregroundStyle(Brand.orange) }
                Spacer(minLength: 0)
            }
            .font(.caption).padding(.horizontal, 12).padding(.vertical, 4)
            .background(Color.primary.opacity(0.04))
            output
        }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            IconButton(symbol: "chevron.left", help: "Back  (esc)") { store.closeLogs() }
            Text(tail.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 150, alignment: .leading)
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter logs", text: $tail.query).textFieldStyle(.plain)
            IconButton(symbol: tail.follow ? "arrow.down.to.line.compact" : "pause", help: tail.follow ? "Following new lines. Click to pause." : "Paused. Click to follow.", tint: tail.follow ? Brand.green : nil) {
                tail.follow.toggle()
            }
            IconButton(symbol: "doc.on.doc", help: "Copy what you see") { Actions.copy(tail.text); store.flash("Copied the logs") }
            IconButton(symbol: "trash", help: "Clear the view. The file is not touched.") { tail.clear() }
            IconButton(symbol: "terminal", help: "Open in Terminal") { store.openLogsInTerminal() }
        }
        .padding(.horizontal, 8).padding(.vertical, 9)
    }

    @ViewBuilder private var output: some View {
        let shown = tail.shown
        if shown.isEmpty {
            VStack(spacing: 6) {
                Text(tail.lines.isEmpty ? "No output yet" : "No lines match “\(tail.query)”").font(.system(size: 13, weight: .semibold))
                if tail.lines.isEmpty { Text("New lines appear here as the server prints them.").font(.callout).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(shown) { l in
                            Text(l.text.isEmpty ? " " : l.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(color(l.kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(l.id)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .onChange(of: shown.last?.id) { _, id in
                    if tail.follow, let id { proxy.scrollTo(id, anchor: .bottom) }
                }
                .onChange(of: tail.follow) { _, on in
                    if on, let id = shown.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
                .onAppear { if let id = shown.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
    }

    private func color(_ k: LogLine.Kind) -> Color {
        switch k {
        case .plain: return .primary
        case .error: return Brand.alert
        case .warn: return Brand.orange
        case .marker: return .secondary
        }
    }
}
