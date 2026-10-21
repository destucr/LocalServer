import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published private(set) var entries: [PortEntry] = []
    @Published var query = ""
    @Published var showAll = false
    @Published var message: String?
    @Published var busy: Set<String> = []
    @Published var armedKill: String?
    static let shared = Store()
    let tunnels = TunnelManager()

    private var messageTask: Task<Void, Never>?

    init() {
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [tunnels] _ in
            MainActor.assumeIsolated { tunnels.stopAll() }
        }
    }

    var visible: [PortEntry] {
        entries.filter { e in
            (showAll || e.kind != .other) &&
            (query.isEmpty || [e.title, e.group, e.command, String(e.port)].contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var groups: [(name: String, path: String?, entries: [PortEntry])] {
        var order: [String] = []
        var map: [String: [PortEntry]] = [:]
        for e in visible {
            if map[e.group] == nil { order.append(e.group) }
            map[e.group, default: []].append(e)
        }
        return order.map { (name: $0, path: map[$0]?.first?.projectPath, entries: map[$0]!) }
    }

    var count: Int { entries.filter { $0.kind != .other }.count }

    func refresh() async {
        let result = await Task.detached(priority: .utility) { Scanner.scan() }.value
        if result != entries { entries = result }
    }

    func flash(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.message = nil }
        }
    }

    // MARK: Actions

    func open(_ e: PortEntry) { NSWorkspace.shared.open(e.localURL) }

    func kill(_ e: PortEntry) {
        // Databases need a second click; everything else is one click.
        if e.kind == .database || e.container != nil, armedKill != e.id {
            armedKill = e.id
            Task { try? await Task.sleep(for: .seconds(3)); if armedKill == e.id { armedKill = nil } }
            return
        }
        armedKill = nil
        perform(e, success: "Stopped :\(e.port)") { try await Actions.kill(e) }
    }

    func restart(_ e: PortEntry) {
        perform(e, success: "Restarted :\(e.port)") { try await Actions.restart(e) }
    }

    func tail(_ e: PortEntry) {
        do { try Actions.tail(e) } catch { flash(error.localizedDescription) }
    }

    private func perform(_ e: PortEntry, success: String, _ work: @escaping () async throws -> Void) {
        busy.insert(e.id)
        Task {
            do { try await work(); flash(success) } catch { flash(error.localizedDescription) }
            try? await Task.sleep(for: .milliseconds(600))
            await refresh()
            busy.remove(e.id)
        }
    }

    func copyLocal(_ e: PortEntry) { Actions.copy(e.localURL.absoluteString); flash("Copied \(e.localURL.absoluteString)") }

    func copyLAN(_ e: PortEntry) {
        guard let ip = Actions.lanAddress() else { flash("No LAN address found"); return }
        let url = "http://\(ip):\(e.port)"
        Actions.copy(url)
        flash(e.lanExposed ? "Copied \(url)" : "Copied \(url) — bound to localhost only, LAN can't reach it")
    }

    func toggleTunnel(_ e: PortEntry) {
        if tunnels.tunnels[e.port] != nil { tunnels.stop(port: e.port); return }
        do { try tunnels.start(port: e.port); flash("Starting tunnel…") } catch { flash(error.localizedDescription) }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { flash("Launch at login needs the app in /Applications (./build.sh install)") }
            objectWillChange.send()
        }
    }
}
