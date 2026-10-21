import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store
    @FocusState private var filterFocused: Bool

    // Fixed so the popover never changes size while you filter or toggle.
    private let listHeight: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 0) {
                if let port = store.portQuery { PortCard(port: port) }
                if store.visible.isEmpty {
                    if store.portQuery == nil {
                        VStack(spacing: 6) {
                            Image(systemName: "powersleep").font(.title2).foregroundStyle(.secondary)
                            Text(store.query.isEmpty ? "Nothing is listening" : "No matches").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Spacer(minLength: 0)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(store.groups, id: \.name) { g in
                                Section {
                                    ForEach(g.entries) { RowView(entry: $0) }
                                } header: {
                                    GroupHeader(name: g.name, path: g.path)
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: listHeight)
            Divider()
            footer
        }
        .frame(width: 440)
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidShow)) { _ in
            store.query = ""
            filterFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter, or type a port (3000)", text: $store.query)
                .textFieldStyle(.plain)
                .focused($filterFocused)
                .onSubmit { if let first = store.visible.first { store.primary(first) } }
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Rescan now")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if let m = store.message {
                Text(m).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.quaternary.opacity(0.5))
                    .transition(.opacity)
            }
            HStack {
                Text("\(store.visible.count) listening").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("About LocalServer \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")") {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.orderFrontStandardAboutPanel(nil)
                    }
                    Text("Shortcut: \(AppDelegate.shortcutLabel)")
                    Divider()
                    Toggle("Show system & apps", isOn: $store.showAll)
                    Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
                    Divider()
                    Button("Quit LocalServer") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
        }
        .animation(.default, value: store.message)
    }
}

/// "Is port N free? Who has it? What's the next one?" — shown when the filter is a port number.
struct PortCard: View {
    @EnvironmentObject var store: Store
    let port: Int

    var body: some View {
        let owners = store.entries.filter { $0.port == port }
        let inUse = !owners.isEmpty || !Ports.isFree(port)
        let next = Ports.nextFree(after: port, taken: Set(store.entries.map(\.port)))
        HStack(spacing: 10) {
            Image(systemName: inUse ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(inUse ? .orange : .green).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(inUse ? "Port \(String(port)) is in use" : "Port \(String(port)) is free").font(.system(size: 13, weight: .semibold))
                Text(!inUse ? "Go ahead and start your server"
                     : owners.isEmpty ? "Held by a process LocalServer can't see. Next free port is \(String(next))."
                     : "Stop it below to free the port. Next free port is \(String(next)).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if inUse {
                Button("Copy \(String(next))") { Actions.copy(String(next)); store.flash("Copied \(next), the next free port") }
                    .controlSize(.small).help("Copy the next free port number")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background((inUse ? Color.orange : Color.green).opacity(0.10))
    }
}

struct GroupHeader: View {
    let name: String
    let path: String?
    var body: some View {
        HStack(spacing: 6) {
            Text(name.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if let path {
                Spacer()
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless).help(abbreviateHome(path))
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}

struct RowView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var tunnels: TunnelManager
    let entry: PortEntry
    @State private var hover = false

    init(entry: PortEntry) {
        self.entry = entry
        _tunnels = ObservedObject(wrappedValue: Store.shared.tunnels)
    }

    private var armed: Bool { store.armedKill == entry.id }
    private var busyLabel: String? { store.busy[entry.id] }
    private var copied: Bool { store.copiedID == entry.id }
    private var canRestart: Bool { entry.container != nil || entry.restart != nil }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.green).frame(width: 7, height: 7)
            Text(String(entry.port))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(entry.title).font(.system(size: 13)).lineLimit(1)
                    if entry.web == .api {
                        Text("API").font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.secondary.opacity(0.18), in: Capsule()).foregroundStyle(.secondary)
                            .help("Answers HTTP but not with a web page")
                    }
                    if entry.lanExposed {
                        Image(systemName: "wifi").font(.system(size: 9)).foregroundStyle(.orange)
                            .help("Anyone on your network can reach this server (it listens on all interfaces)")
                    }
                }
                // Show exactly what the button will copy, so there is nothing to guess.
                if entry.web != .page {
                    Text(entry.address).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).fixedSize()
                }
                if let t = tunnels.tunnels[entry.port] { TunnelLine(tunnel: t) }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            if let label = busyLabel {
                Text(label).font(.caption).foregroundStyle(.secondary)
                ProgressView().controlSize(.small)
            } else {
                if armed {
                    Text("Stop \(entry.title)?").font(.caption).foregroundStyle(.red)
                } else if hover {
                    secondaryActions
                } else if let up = entry.uptime {
                    Text(up).font(.caption).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                }
                mainButton
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(height: 44)
        .background(hover ? Color.primary.opacity(0.06) : .clear)
        .onHover { hover = $0 }
        .help("PID \(entry.pid.map(String.init) ?? "-")  \(entry.command)")
    }

    @ViewBuilder private var mainButton: some View {
        if armed {
            Button("Yes, stop") { store.kill(entry) }
                .controlSize(.small).buttonStyle(.borderedProminent).tint(.red)
        } else if entry.web == .page {
            Button("Open") { store.open(entry) }
                .controlSize(.small).buttonStyle(.bordered)
                .help("Open \(entry.address) in your browser")
        } else {
            Button { store.copyLocal(entry) } label: {
                Text(copied ? "Copied ✓" : entry.copyLabel).frame(minWidth: 70)
            }
            .controlSize(.small).buttonStyle(.bordered)
            .tint(copied ? .green : nil)
            .help("Copy \(entry.address)")
        }
    }

    private var secondaryActions: some View {
        HStack(spacing: 0) {
            if entry.web == .api {
                IconButton(symbol: "arrow.up.forward.square", help: "Open \(entry.address) in your browser") { store.open(entry) }
            }
            IconButton(symbol: "arrow.clockwise", help: canRestart ? "Restart with the same command" : "Can't restart: LocalServer doesn't know how this was started")
                { store.restart(entry) }
                .disabled(!canRestart)
            IconButton(symbol: "text.alignleft", help: "Follow the logs in Terminal") { store.tail(entry) }
            shareMenu
            IconButton(symbol: "stop.fill", help: "Stop this server", tint: Color.red.opacity(0.75)) { store.kill(entry) }
        }
    }

    private var shareMenu: some View {
        let lan = Actions.lanAddress().map { "http://\($0):\(entry.port)" } ?? "no network found"
        return Menu {
            Button("Copy link for this Mac:  \(entry.address)") { store.copyLocal(entry) }
            Button(entry.lanExposed ? "Copy link for your Wi-Fi:  \(lan)" : "Copy link for your Wi-Fi (won't work, localhost only)") {
                store.copyLAN(entry)
            }
            Divider()
            if tunnels.tunnels[entry.port] != nil {
                Button("Stop the internet link") { store.toggleTunnel(entry) }
            } else if let p = TunnelManager.provider {
                Button("Get a temporary internet link (via \(p.name))") { store.toggleTunnel(entry) }
            } else {
                Button("Get an internet link (needs cloudflared: brew install cloudflared)") { store.toggleTunnel(entry) }
            }
        } label: {
            Image(systemName: "square.and.arrow.up").frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .disabled(entry.web == .none)
        .help("Share this server")
    }
}

struct TunnelLine: View {
    @ObservedObject var tunnel: Tunnel
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe").font(.caption2)
            switch tunnel.state {
            case .starting: Text("Creating public link…")
            case .running(let url):
                Button(url) { Actions.copy(url); Store.shared.flash("Public link copied: \(url)") }
                    .buttonStyle(.plain).underline().help("Public link, click to copy again")
            case .failed(let why): Text("Public link failed (\(why))")
            }
        }
        .font(.caption).foregroundStyle(.blue).lineLimit(1)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color?
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 22, height: 22).contentShape(Rectangle())
                .foregroundStyle(tint ?? (enabled ? Color.primary : Color.secondary.opacity(0.4)))
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
