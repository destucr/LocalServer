import SwiftUI

/// Colors for the tile behind each server type, in the style of an architecture diagram. All hold white icons at 3:1 or better.
extension StackType {
    var tileColor: Color {
        switch self {
        case .web: return Color(red: 0.31, green: 0.27, blue: 0.90)
        case .api: return Color(red: 0.55, green: 0.28, blue: 0.86)
        case .database: return Color(red: 0.12, green: 0.42, blue: 0.82)
        case .cache: return Color(red: 0.84, green: 0.30, blue: 0.25)
        case .search: return Color(red: 0.72, green: 0.45, blue: 0.05)
        case .mail: return Color(red: 0.08, green: 0.52, blue: 0.56)
        case .storage: return Color(red: 0.36, green: 0.43, blue: 0.54)
        case .worker: return Color(red: 0.78, green: 0.27, blue: 0.50)
        case .container: return Color(red: 0.05, green: 0.50, blue: 0.74)
        case .server: return Color(red: 0.36, green: 0.40, blue: 0.48)
        case .missing: return .clear
        }
    }
}

/// The running stack drawn like an architecture diagram: sources on the left, what they depend on to the right.
/// Drag a node to move it; the position is remembered.
struct StackMapView: View {
    @EnvironmentObject var store: Store
    @State private var selected: String?
    @State private var dragging: [String: CGSize] = [:]
    @State private var panLive: CGSize?
    @State private var zoomLive: CGFloat?

    private let stripHeight: CGFloat = 78
    private let tile: CGFloat = 40

    var body: some View {
        let map = store.stack
        if map.nodes.filter({ $0.role != .missing }).count < 2 {
            VStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.title2).foregroundStyle(.secondary)
                Text("Nothing to connect yet").font(.system(size: 14, weight: .semibold))
                Text("Start two or more servers and their links show up here.").font(.callout).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                let layout = Layout(map: map, size: geo.size, stripHeight: stripHeight)
                let points = layout.point.reduce(into: [String: CGPoint]()) { out, kv in
                    let off = dragging[kv.key] ?? store.mapOffsets[kv.key] ?? .zero
                    out[kv.key] = CGPoint(x: min(max(kv.value.x + off.width, 40), geo.size.width - 40),
                                          y: min(max(kv.value.y + off.height, 34), geo.size.height - 54))
                }
                let pan = panLive ?? store.mapPan
                let zoom = zoomLive ?? store.mapZoom

                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        drawProjects(in: &ctx, points: points, map: map, width: layout.nodeW)
                        for e in map.edges { draw(edge: e, in: &ctx, points: points, map: map) }
                    }
                    ForEach(map.edges.filter { $0.count > 1 }, id: \.self) { e in
                        if let a = points[e.from], let b = points[e.to] {
                            Text("×\(e.count)").font(.system(size: 9, weight: .semibold)).foregroundStyle(Brand.primaryText)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(.regularMaterial))
                                .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                                .allowsHitTesting(false)
                        }
                    }
                    ForEach(map.nodes) { n in
                        if let p = points[n.id] {
                            NodeView(node: n, map: map, selected: selected == n.id, dimmed: dimmed(n, map), width: layout.nodeW, tile: tile)
                                .transition(.node)
                                .onTapGesture { selected = selected == n.id ? nil : n.id }
                                .gesture(
                                    DragGesture(minimumDistance: 4, coordinateSpace: .named("map"))
                                        .onChanged { v in
                                            let base = store.mapOffsets[n.id] ?? .zero
                                            dragging[n.id] = CGSize(width: base.width + v.translation.width, height: base.height + v.translation.height)
                                        }
                                        .onEnded { _ in
                                            if let d = dragging[n.id] { store.setMapOffset(n.id, d) }
                                            dragging[n.id] = nil
                                        }
                                )
                                .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
                                .contextMenu {
                                    if let e = store.entries.first(where: { $0.id == n.entryID }) { ServerMenu(entry: e) }
                                    else { Text("\(n.title)\(n.port.map { " :\($0)" } ?? "")") }
                                }
                                .position(x: p.x, y: p.y + 17)
                        }
                    }
                    if !layout.isolated.isEmpty {
                        Text("No connection seen").font(.caption).foregroundStyle(.secondary).position(x: 56, y: geo.size.height - stripHeight - 4)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .coordinateSpace(name: "map")
                .scaleEffect(zoom)
                .offset(pan)
                // The whole area: drag empty space to pan, pinch to zoom, click it to deselect.
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .onTapGesture { selected = nil }
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { v in panLive = CGSize(width: store.mapPan.width + v.translation.width, height: store.mapPan.height + v.translation.height) }
                        .onEnded { _ in if let p = panLive { store.setMapView(pan: p, zoom: store.mapZoom) }; panLive = nil }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { zoomLive = store.mapZoom * $0.magnification }
                        .onEnded { _ in if let z = zoomLive { store.setMapView(pan: store.mapPan, zoom: z) }; zoomLive = nil }
                )
                .clipped()
                .overlay(alignment: .topTrailing) { MapControls() }
                .overlay(alignment: .bottom) { if let id = selected, let n = map.node(id) { DetailCard(node: n, map: map, close: { selected = nil }).transition(.sheet(from: .bottom)) } }
                .animation(Motion.pop, value: selected)
                .overlay(alignment: .bottomLeading) { if selected == nil { Legend().padding(.horizontal, 12).padding(.bottom, 2) } }
            }
            .padding(.vertical, 8)
        }
    }

    /// A faint labelled box around each project's servers, like the network boxes in a cloud diagram.
    /// Skipped when boxes would overlap, because a messy box is worse than none.
    private func drawProjects(in ctx: inout GraphicsContext, points: [String: CGPoint], map: StackMap, width: CGFloat) {
        var boxes: [(name: String, rect: CGRect)] = []
        for (name, nodes) in Dictionary(grouping: map.nodes.filter { $0.role != .missing && $0.project != nil && points[$0.id] != nil }, by: { $0.project! }) {
            let ps = nodes.compactMap { points[$0.id] }
            guard let minX = ps.map(\.x).min(), let maxX = ps.map(\.x).max(), let minY = ps.map(\.y).min(), let maxY = ps.map(\.y).max() else { continue }
            boxes.append((name, CGRect(x: minX - width / 2 - 10, y: minY - tile / 2 - 24, width: maxX - minX + width + 20, height: maxY - minY + tile + 34 + 34)))
        }
        for i in boxes.indices { for j in boxes.indices where j > i && boxes[i].rect.intersects(boxes[j].rect) { return } }
        for b in boxes {
            let path = RoundedRectangle(cornerRadius: 14, style: .continuous).path(in: b.rect)
            ctx.fill(path, with: .color(Color.primary.opacity(0.035)))
            ctx.stroke(path, with: .color(Color.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            ctx.draw(Text(b.name).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.secondary),
                     at: CGPoint(x: b.rect.minX + 11, y: b.rect.minY + 8), anchor: .topLeading)
        }
    }

    private func dimmed(_ n: StackNode, _ map: StackMap) -> Bool {
        guard let s = selected, s != n.id else { return false }
        return !map.edges.contains { ($0.from == s && $0.to == n.id) || ($0.to == s && $0.from == n.id) }
    }

    private func draw(edge e: StackEdge, in ctx: inout GraphicsContext, points: [String: CGPoint], map: StackMap) {
        guard let a = points[e.from], let b = points[e.to] else { return }
        let half = tile / 2 + 3
        let forward = b.x > a.x + 20
        let start = forward ? CGPoint(x: a.x + half, y: a.y) : CGPoint(x: a.x, y: a.y + half)
        let end = forward ? CGPoint(x: b.x - half - 3, y: b.y) : CGPoint(x: b.x, y: b.y + half + 3)
        var path = Path()
        path.move(to: start)
        let dx = max(abs(end.x - start.x) * 0.5, 24)
        let c1 = CGPoint(x: start.x + (forward ? dx : 0), y: start.y + (forward ? 0 : 40))
        let c2 = CGPoint(x: end.x - (forward ? dx : 0), y: end.y + (forward ? 0 : 40))
        path.addCurve(to: end, control1: c1, control2: c2)

        let target = map.node(e.to)
        let failing = e.broken || (target?.status ?? 0) >= 500
        let involved = selected == nil || selected == e.from || selected == e.to
        let color: Color = failing ? Brand.alert : (e.configured ? Color.secondary : Brand.primaryText)
        let style = StrokeStyle(lineWidth: e.configured ? 1.3 : 1.8, lineCap: .round, dash: e.configured ? [4, 4] : [])
        ctx.stroke(path, with: .color(color.opacity(involved ? (e.configured ? 0.75 : 0.85) : 0.18)), style: style)

        let ang = atan2(end.y - c2.y, end.x - c2.x)
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - 7 * cos(ang - 0.45), y: end.y - 7 * sin(ang - 0.45)))
        head.addLine(to: CGPoint(x: end.x - 7 * cos(ang + 0.45), y: end.y - 7 * sin(ang + 0.45)))
        head.closeSubpath()
        ctx.fill(head, with: .color(color.opacity(involved ? 0.9 : 0.2)))
    }

    /// Columns by dependency depth, rows linked-aware. Servers with no links sit in a strip at the bottom.
    struct Layout {
        var point: [String: CGPoint] = [:]
        var isolated: [StackNode] = []
        var nodeW: CGFloat = 96

        init(map: StackMap, size: CGSize, stripHeight: CGFloat) {
            let linked = Set(map.edges.flatMap { [$0.from, $0.to] })
            let connected = map.nodes.filter { linked.contains($0.id) }
            isolated = map.nodes.filter { !linked.contains($0.id) && $0.role != .missing }
            let layers = map.layers()
            let cols = max((connected.compactMap { layers[$0.id] }.max() ?? 0) + 1, 1)
            let colW = size.width / CGFloat(cols)
            nodeW = min(104, colW - 14)
            let top: CGFloat = 34
            let bottom: CGFloat = isolated.isEmpty ? 58 : stripHeight + 64
            let height = max(size.height - top - bottom, 60)
            let lists: [[StackNode]] = (0..<cols).map { c in
                connected.filter { layers[$0.id] == c }.sorted { ($0.project ?? "~", $0.port ?? 0) < ($1.project ?? "~", $1.port ?? 0) }
            }
            let rowGap = min(88, height / CGFloat(max(lists.map(\.count).max() ?? 1, 1)))
            let mid = top + height / 2
            var y: [String: CGFloat] = [:]

            for c in 0..<cols {
                var list = lists[c]
                if c == 0 {
                    for (i, n) in list.enumerated() { y[n.id] = mid + (CGFloat(i) - CGFloat(list.count - 1) / 2) * rowGap }
                } else {
                    func desired(_ n: StackNode) -> CGFloat {
                        let ys = map.edges.compactMap { e -> CGFloat? in
                            if e.to == n.id, let v = y[e.from] { return v }
                            if e.from == n.id, let v = y[e.to] { return v }
                            return nil
                        }
                        return ys.isEmpty ? mid : ys.reduce(0, +) / CGFloat(ys.count)
                    }
                    list.sort { desired($0) < desired($1) }
                    var last = -CGFloat.infinity
                    for n in list { let v = max(desired(n), last + rowGap); y[n.id] = v; last = v }
                    let overflow = last - (top + height)
                    if overflow > 0 { for n in list { y[n.id]! -= overflow } }
                }
                for n in list { point[n.id] = CGPoint(x: colW * (CGFloat(c) + 0.5), y: y[n.id]!) }
            }
            let perRow = max(Int(size.width / (nodeW + 8)), 1)
            for (i, n) in isolated.enumerated() {
                let row = i / perRow, col = i % perRow
                point[n.id] = CGPoint(x: 14 + nodeW / 2 + CGFloat(col) * (nodeW + 8), y: size.height - stripHeight - 18 + CGFloat(row) * 84)
            }
        }
    }
}

/// One server as a tile with a glyph for its type, and its port and name underneath.
private struct NodeView: View {
    let node: StackNode
    let map: StackMap
    let selected: Bool
    let dimmed: Bool
    let width: CGFloat
    let tile: CGFloat

    private var failing: Bool { node.role == .missing || (node.status ?? 0) >= 500 }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if node.type == .missing {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Brand.alert, style: StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
                    Image(systemName: node.type.symbol).font(.system(size: 19, weight: .semibold)).foregroundStyle(Brand.alert)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(node.type.tileColor)
                    Image(systemName: node.type.symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                }
            }
            .frame(width: tile, height: tile)
            .overlay(alignment: .topTrailing) {
                if node.role != .missing {
                    Circle().fill(failing ? Brand.alert : (node.role == .client ? Color.secondary : Brand.mint))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                        .offset(x: 4, y: -4)
                }
            }
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Brand.primary, lineWidth: 2.5).padding(-4) }
            }

            VStack(spacing: 0) {
                Text(node.port.map { String($0) } ?? "worker").font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                Text(node.title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: width)
        }
        .frame(width: width, height: tile + 34)
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(Rectangle())
        .tip(summary)
    }

    private var summary: String {
        var lines = ["\(node.type.label): \(node.title)\(node.port.map { " :\($0)" } ?? "")"]
        let uses = map.uses(node.id), by = map.usedBy(node.id)
        if !uses.isEmpty { lines.append("Uses " + uses.map { "\($0.title) :\($0.port ?? 0)" }.joined(separator: ", ")) }
        if !by.isEmpty { lines.append("Used by " + by.map { "\($0.title)\($0.port.map { " :\($0)" } ?? "")" }.joined(separator: ", ")) }
        for b in map.brokenLinks(node.id) { lines.append("Expects :\(b.to.split(separator: ":").last ?? ""), nothing there") }
        return lines.joined(separator: "\n")
    }
}

private struct DetailCard: View {
    @EnvironmentObject var store: Store
    let node: StackNode
    let map: StackMap
    let close: () -> Void

    var body: some View {
        let entry = store.entries.first { $0.id == node.entryID }
        let uses = map.uses(node.id), broken = map.brokenLinks(node.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: node.type.symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(node.type.tileColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("\(node.title)\(node.port.map { " :\($0)" } ?? "")").font(.system(size: 13, weight: .semibold))
                Text(node.type.label + (node.project.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { close() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            let liveBy = map.usedBy(node.id, live: true), envBy = map.usedBy(node.id, live: false)
            let liveUses = uses.filter { u in map.edges.contains { $0.from == node.id && $0.to == u.id && !$0.configured } }
            let envUses = uses.filter { u in !liveUses.contains(u) }
            if !liveBy.isEmpty { Text("Connected from " + names(liveBy)).font(.caption).foregroundStyle(.secondary) }
            if !liveUses.isEmpty { Text("Connected to " + names(liveUses)).font(.caption).foregroundStyle(.secondary) }
            if !envBy.isEmpty { Text("Its project's .env points here from " + names(envBy) + ". No connection seen yet.").font(.caption).foregroundStyle(.secondary) }
            if !envUses.isEmpty { Text("This project's .env points at " + names(envUses) + ". No connection seen yet.").font(.caption).foregroundStyle(.secondary) }
            ForEach(broken, id: \.to) { b in
                Label("Expects :\(b.to.split(separator: ":").last ?? "") (\(b.hint ?? "config")), but nothing is listening", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Brand.alert)
            }
            if let e = entry {
                HStack(spacing: 8) {
                    if e.web == .page { Button("Open") { store.open(e) }.buttonStyle(PillButton(tone: .open, width: 64)) }
                    else { Button(e.copyLabel) { store.copyLocal(e) }.buttonStyle(PillButton(tone: .quiet, width: 84)) }
                    Button("Stop") { store.kill(e) }.buttonStyle(PillButton(tone: .stop, width: 64))
                    if !liveBy.isEmpty { Text("\(liveBy.count) connected to it").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .padding(8)
    }

    private func names(_ n: [StackNode]) -> String { n.map { "\($0.title)\($0.port.map { " :\($0)" } ?? "")" }.joined(separator: ", ") }
}

private struct Legend: View {
    var body: some View {
        HStack(spacing: 12) {
            item(Brand.primaryText, dash: false, "connected")
            item(Color.secondary, dash: true, "in .env, not seen")
            item(Brand.alert, dash: false, "error")
            Text("·  drag or pinch").foregroundStyle(.secondary)
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
    }

    private func item(_ color: Color, dash: Bool, _ text: String) -> some View {
        HStack(spacing: 4) {
            Path { $0.move(to: CGPoint(x: 0, y: 3)); $0.addLine(to: CGPoint(x: 16, y: 3)) }
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: dash ? [3, 3] : []))
                .frame(width: 16, height: 6)
            Text(text)
        }
    }
}

/// Zoom in, zoom out and reset, for people without a trackpad.
private struct MapControls: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 2) {
            if store.mapIsCustomised {
                Button("Reset") { withAnimation(Motion.anim) { store.resetMapLayout() } }
                    .buttonStyle(PillButton(tone: .quiet, width: 52)).hoverTip("Back to the automatic layout", tint: Brand.primary)
            }
            IconButton(symbol: "minus", help: "Zoom out") { withAnimation(Motion.anim) { store.setMapView(pan: store.mapPan, zoom: store.mapZoom - 0.2) } }
            IconButton(symbol: "plus", help: "Zoom in") { withAnimation(Motion.anim) { store.setMapView(pan: store.mapPan, zoom: store.mapZoom + 0.2) } }
        }
        .padding(8)
    }
}
