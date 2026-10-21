import SwiftUI

/// The app's own palette, taken from the icon: indigo for actions, mint for "running". Red is kept for danger.
enum Brand {
    private static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static let primary = adaptive(NSColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1), NSColor(red: 0.42, green: 0.44, blue: 0.96, alpha: 1))
    static let primaryText = adaptive(NSColor(red: 0.26, green: 0.22, blue: 0.80, alpha: 1), NSColor(red: 0.65, green: 0.67, blue: 0.99, alpha: 1))
    static let mint = Color(red: 0.30, green: 0.84, blue: 0.52)
    static let green = adaptive(NSColor(red: 0.08, green: 0.50, blue: 0.27, alpha: 1), NSColor(red: 0.16, green: 0.60, blue: 0.35, alpha: 1))
    static let red = adaptive(NSColor(red: 0.82, green: 0.16, blue: 0.22, alpha: 1), NSColor(red: 0.90, green: 0.30, blue: 0.34, alpha: 1))
}

/// Color tells you what a button is for: blue is the main action, green brings something back, red stops something.
enum Tone {
    case open, start, quiet, copied, stop

    var fill: Color {
        switch self {
        case .open: return Brand.primary
        case .start: return Brand.green
        case .stop: return Brand.red
        case .quiet: return Brand.primary.opacity(0.14)
        case .copied: return Brand.green.opacity(0.18)
        }
    }
    var text: Color {
        switch self {
        case .open, .start, .stop: return .white
        case .quiet: return Brand.primaryText
        case .copied: return Brand.green
        }
    }
}

struct PillButton: ButtonStyle {
    let tone: Tone
    var width: CGFloat = 78
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tone.text)
            .frame(width: width, height: 22)
            .background(tone.fill.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(enabled ? 1 : 0.45)
    }
}

enum Theme {
    /// Screenshots are rendered offscreen where there is nothing to blur, so they use a flat tint instead.
    static var flat = false
    /// Screenshot only: a solid color behind everything, used to recover transparency.
    static var matte: Color?
}

/// Project header bands: translucent, so rows blur underneath as they scroll past.
struct BandBackground: View {
    var body: some View {
        if Theme.flat {
            Color.primary.opacity(0.07)
        } else {
            // The thinnest material keeps the blur but stays see-through; the tint separates the band from the rows.
            Rectangle().fill(.ultraThinMaterial).overlay(Color.primary.opacity(0.05))
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @FocusState private var filterFocused: Bool

    // Fixed so the popover never changes size while you filter or toggle.
    private let listHeight: CGFloat = 440

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 0) {
                if let port = store.portQuery { PortCard(port: port) }
                if store.groups.isEmpty {
                    if store.portQuery == nil {
                        EmptyState()
                    } else {
                        Spacer(minLength: 0)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(store.groups) { g in
                                Section {
                                    ForEach(g.running) { RowView(entry: $0).transition(.opacity.combined(with: .move(edge: .top))) }
                                    ForEach(g.stopped) { StoppedRow(server: $0).transition(.opacity) }
                                } header: {
                                    GroupHeader(group: g)
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: listHeight)
            .overlay(alignment: .bottom) {
                if let m = store.message {
                    Text(m).font(.caption).foregroundStyle(.primary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                        .padding(8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.anim, value: store.message)
            Divider()
            footer
        }
        .frame(width: 470)
        .tint(Brand.primary)
        .background { if let m = Theme.matte { Rectangle().fill(m) } }
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
            HStack(spacing: 10) {
                if let hint = store.hoverHint {
                    Text(hint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("\(store.count) running").font(.caption).foregroundStyle(.secondary)
                    if !store.stopped.isEmpty {
                        Button(store.showStopped ? "Hide stopped" : "Show \(store.stopped.count) stopped") { store.showStopped.toggle() }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(Brand.primaryText)
                    }
                }
                Spacer()
                Menu {
                    Button("About LocalServer \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")") {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.orderFrontStandardAboutPanel(nil)
                    }
                    Text("Shortcut: \(AppDelegate.shortcutLabel)")
                    Divider()
                    Toggle("Show stopped servers", isOn: $store.showStopped)
                    Toggle("Notify when a server stops", isOn: $store.notifyOnStop)
                    Toggle("Show system & apps", isOn: $store.showAll)
                    Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
                    Divider()
                    Button("Quit LocalServer") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
        }
    }
}

/// Shown when the list is empty: nothing running yet, or the filter matches nothing.
struct EmptyState: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 7) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
                        .frame(width: 70, height: 28)
                        .overlay(alignment: .leading) {
                            HStack(spacing: 8) {
                                Circle().strokeBorder(Color.secondary.opacity(0.8), lineWidth: 1.5).frame(width: 8, height: 8)
                                Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 28, height: 3)
                            }.padding(.leading, 12)
                        }
                }
            }
            if store.query.isEmpty {
                Text("Nothing is running").font(.system(size: 14, weight: .semibold))
                Text("Start a dev server and it shows up here.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("No match for “\(store.query)”").font(.system(size: 14, weight: .semibold))
                Button("Clear filter") { store.query = "" }.controlSize(.small)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Is port N free? Who has it? What's the next one?" Shown when the filter is a port number.
struct PortCard: View {
    @EnvironmentObject var store: Store
    let port: Int

    var body: some View {
        let owners = store.entries.filter { $0.port == port }
        let inUse = !owners.isEmpty || !Ports.isFree(port)
        let next = Ports.nextFree(after: port, taken: Set(store.entries.map(\.port)))
        HStack(spacing: 10) {
            Image(systemName: inUse ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(inUse ? Color.orange : Brand.green).font(.title3)
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
                    .buttonStyle(PillButton(tone: .quiet, width: 74)).help("Copy the next free port number")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background((inUse ? Color.orange : Brand.green).opacity(0.12))
    }
}

struct GroupHeader: View {
    @EnvironmentObject var store: Store
    let group: ProjectGroup

    private var restartable: Int { group.running.filter { $0.container != nil || $0.restart != nil }.count }
    private var stoppable: Int { group.running.filter { $0.kind != .other }.count }
    private var startable: Int { group.stopped.filter(\.canStart).count }

    var body: some View {
        HStack(spacing: 6) {
            if group.name == "Pinned" { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.secondary) }
            Text(group.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Menu {
                if let path = group.path {
                    ForEach(Editors.installed, id: \.name) { ed in
                        Button("Open in \(ed.name)") { store.openProject(path, in: ed.url) }
                    }
                    Button("Open Terminal here") { Editors.openTerminal(at: path) }
                    Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                    Divider()
                }
                if startable > 0 { Button("Start \(startable) stopped") { store.startAll(group) } }
                if restartable > 0 { Button("Restart \(restartable) running") { store.restartAll(group) } }
                if stoppable > 0 { Button("Stop all \(stoppable)…") { store.stopAll(group) } }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary).frame(width: 22, height: 18).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(group.path.map { "Project actions for \(abbreviateHome($0))" } ?? "Group actions")
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BandBackground())
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
    private var busyLabel: String? { store.busy[entry.key] }
    private var copied: Bool { store.copiedID == entry.id }
    private var canRestart: Bool { entry.container != nil || entry.restart != nil }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Brand.mint).frame(width: 7, height: 7)
            Text(String(entry.port))
                .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(store.displayName(entry)).font(.system(size: 13)).lineLimit(1)
                    if store.isRenamed(entry) {
                        Text(entry.title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if entry.web == .api {
                        Text("API").font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.secondary.opacity(0.2), in: Capsule()).foregroundStyle(.secondary)
                            .help("Answers HTTP but not with a web page")
                    }
                    health
                    if entry.lanExposed {
                        Image(systemName: "wifi").font(.system(size: 9)).foregroundStyle(.orange)
                            .help("Anyone on your network can reach this server (it listens on all interfaces)")
                    }
                    if store.isPinned(entry.key) { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.secondary) }
                }
                // Show exactly what the button will copy, so there is nothing to guess.
                if entry.web != .page {
                    Text(entry.address).font(.system(size: 11)).foregroundStyle(.secondary)
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
                    Text("up \(up)").font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                        .help("Running for \(up)")
                }
                mainButton
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(height: 44)
        .background(store.recent.contains(entry.key) ? Brand.mint.opacity(0.20) : (hover ? Color.primary.opacity(0.07) : .clear))
        .onHover { hover = $0; store.setHover(entry.key, $0) }
        .help("PID \(entry.pid.map(String.init) ?? "-")  \(entry.command)")
    }

    @ViewBuilder private var health: some View {
        if let s = entry.status, let ms = entry.ms {
            if s >= 500 {
                Text("\(s)").font(.system(size: 10, weight: .bold)).foregroundStyle(.red).help("The server answered HTTP \(s)")
            } else {
                Text("\(ms) ms").font(.system(size: 10)).foregroundStyle(.secondary).help("HTTP \(s) in \(ms) ms")
            }
        }
    }

    @ViewBuilder private var mainButton: some View {
        if armed {
            Button { store.kill(entry) } label: { Text("Yes, stop") }
                .buttonStyle(PillButton(tone: .stop))
        } else if entry.web == .page {
            Button { store.open(entry) } label: { Text("Open") }
                .buttonStyle(PillButton(tone: .open))
                .help("Open \(entry.address) in your browser  (⌘O)")
        } else {
            Button { store.copyLocal(entry) } label: {
                Text(copied ? "Copied ✓" : entry.copyLabel).animation(Motion.anim, value: copied)
            }
            .buttonStyle(PillButton(tone: copied ? .copied : .quiet))
            .help("Copy \(entry.address)  (⌘C)")
        }
    }

    private var secondaryActions: some View {
        HStack(spacing: 0) {
            if entry.web == .page {
                IconButton(symbol: "doc.on.doc", help: "Copy \(entry.address)  (⌘C)") { store.copyLocal(entry) }
            }
            IconButton(symbol: "arrow.clockwise", help: canRestart ? "Restart with the same command  (⌘R)" : "Can't restart: LocalServer doesn't know how this was started")
                { store.restart(entry) }
                .disabled(!canRestart)
            IconButton(symbol: "text.alignleft", help: "Follow the logs in Terminal  (⌘L)") { store.tail(entry) }
            shareMenu
            IconButton(symbol: "stop.fill", help: "Stop this server  (⌘⌫)", tint: Brand.red) { store.kill(entry) }
            moreMenu
        }
    }

    private var shareMenu: some View {
        let lan = Actions.lanAddress().map { "http://\($0):\(entry.port)" } ?? "no network found"
        return Menu {
            Button("Copy link for this Mac:  \(entry.address)") { store.copyLocal(entry) }
            Button(entry.lanExposed ? "Copy link for your Wi-Fi:  \(lan)" : "Copy link for your Wi-Fi (won't work, localhost only)") {
                store.copyLAN(entry)
            }
            Button("Show QR code to open on your phone…") { store.showQR(entry) }
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

    private var moreMenu: some View {
        Menu {
            Button(store.isPinned(entry.key) ? "Unpin  (⌘P)" : "Pin to top  (⌘P)") { store.togglePin(entry) }
            Button("Rename…") { store.rename(entry) }
            if entry.web == .api { Button("Open \(entry.address) in browser") { store.open(entry) } }
            if let path = entry.projectPath {
                Divider()
                ForEach(Editors.installed, id: \.name) { ed in Button("Open project in \(ed.name)") { store.openProject(path, in: ed.url) } }
                Button("Open Terminal in project") { Editors.openTerminal(at: path) }
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("More: pin, rename, open project")
    }
}

/// A server that ran before and is not running now.
struct StoppedRow: View {
    @EnvironmentObject var store: Store
    let server: KnownServer
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().strokeBorder(Color.secondary, lineWidth: 1).frame(width: 7, height: 7)
            Text(String(server.port)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.names[server.key] ?? server.title).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                Text("stopped").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let label = store.busy[server.key] {
                Text(label).font(.caption).foregroundStyle(.secondary)
                ProgressView().controlSize(.small)
            } else {
                if hover {
                    IconButton(symbol: store.isPinned(server.key) ? "pin.slash" : "pin", help: store.isPinned(server.key) ? "Unpin" : "Pin to top") { store.togglePin(server) }
                    IconButton(symbol: "xmark", help: "Forget this server  (⌘⌫)") { store.forget(server) }
                }
                if server.canStart {
                    Button { store.start(server) } label: { Text("Start") }
                        .buttonStyle(PillButton(tone: .start))
                        .help((server.containerID != nil ? "Start this container again" : "Run it again in \(abbreviateHome(server.start?.cwd ?? ""))") + "  (⌘R)")
                } else {
                    Text("not running").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(height: 44)
        .background(hover ? Color.primary.opacity(0.07) : .clear)
        .onHover { hover = $0; store.setHover(server.key, $0) }
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
        .font(.caption).foregroundStyle(Brand.primaryText).lineLimit(1)
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
                .foregroundStyle(tint ?? (enabled ? Color.primary : Color.secondary.opacity(0.5)))
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
