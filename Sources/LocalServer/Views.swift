import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store

    // Fixed: MenuBarExtra's window grows with content but never shrinks back.
    private let listHeight: CGFloat = 400

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.visible.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "powersleep").font(.title2).foregroundStyle(.secondary)
                    Text(store.query.isEmpty ? "Nothing is listening" : "No matches").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: listHeight, maxHeight: listHeight)
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
                .frame(height: listHeight)
            }
            Divider()
            footer
        }
        .frame(width: 400)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter", text: $store.query)
                .textFieldStyle(.plain)
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
    private var working: Bool { store.busy.contains(entry.id) }
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
                            .help("Reachable from your network (listening on all interfaces)")
                    }
                }
                if let t = tunnels.tunnels[entry.port] { tunnelLine(t) }
            }
            Spacer(minLength: 4)
            if working {
                ProgressView().controlSize(.small)
            } else {
                if hover { secondaryActions } else if let up = entry.uptime {
                    Text(up).font(.caption).foregroundStyle(.tertiary)
                }
                if entry.web == .page {
                    Button("Open") { store.open(entry) }
                        .controlSize(.small).buttonStyle(.bordered)
                } else {
                    Button("Copy") { store.copyLocal(entry) }
                        .controlSize(.small).buttonStyle(.bordered)
                        .help(entry.web == .none ? "Copy localhost:\(entry.port)" : "Copy http://localhost:\(entry.port)")
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(height: 38)
        .background(hover ? Color.primary.opacity(0.06) : .clear)
        .onHover { hover = $0 }
        .help("PID \(entry.pid.map(String.init) ?? "-")  \(entry.command)")
    }

    private var secondaryActions: some View {
        HStack(spacing: 0) {
            if entry.web == .api {
                IconButton(symbol: "arrow.up.forward.square", help: "Open in browser") { store.open(entry) }
            }
            IconButton(symbol: "arrow.clockwise", help: "Restart") { store.restart(entry) }
                .disabled(!canRestart)
            IconButton(symbol: "text.alignleft", help: "Show logs") { store.tail(entry) }
            shareMenu
            IconButton(symbol: armed ? "exclamationmark.triangle.fill" : "stop.fill",
                       help: armed ? "Click again to stop" : "Stop",
                       tint: armed ? .red : Color.red.opacity(0.75)) { store.kill(entry) }
        }
    }

    @ViewBuilder private func tunnelLine(_ t: Tunnel) -> some View {
        TunnelLine(tunnel: t)
    }

    private var shareMenu: some View {
        Menu {
            Button("Copy http://localhost:\(String(entry.port))") { store.copyLocal(entry) }
            Button("Copy LAN URL") { store.copyLAN(entry) }
            Divider()
            if tunnels.tunnels[entry.port] != nil {
                Button("Stop public tunnel") { store.toggleTunnel(entry) }
            } else {
                Button("Share via public tunnel" + (TunnelManager.provider.map { " (\($0.name))" } ?? "")) { store.toggleTunnel(entry) }
            }
        } label: {
            Image(systemName: "square.and.arrow.up").frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .disabled(entry.web == .none)
        .help("Share")
    }
}

struct TunnelLine: View {
    @ObservedObject var tunnel: Tunnel
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe").font(.caption2)
            switch tunnel.state {
            case .starting: Text("Starting \(tunnel.provider) tunnel…")
            case .running(let url):
                Button(url) { Actions.copy(url) }.buttonStyle(.plain).underline().help("Click to copy")
            case .failed(let why): Text("Tunnel failed (\(why))")
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
