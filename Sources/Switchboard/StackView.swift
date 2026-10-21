import SwiftUI

/// The running stack drawn as connected nodes: sources on the left, what they depend on to the right.
struct StackMapView: View {
    @EnvironmentObject var store: Store
    @State private var selected: String?

    private let stripHeight: CGFloat = 44

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
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        for e in map.edges { draw(edge: e, in: &ctx, layout: layout, map: map) }
                    }
                    ForEach(map.nodes) { n in
                        if let p = layout.point[n.id] {
                            NodeView(node: n, map: map, selected: selected == n.id, dimmed: dimmed(n, map), width: layout.nodeW)
                                .position(p)
                                .onTapGesture { selected = selected == n.id ? nil : n.id }
                        }
                    }
                    if !layout.isolated.isEmpty {
                        Text("Not connected").font(.caption).foregroundStyle(.secondary).position(x: 56, y: geo.size.height - stripHeight - 6)
                    }
                }
                .overlay(alignment: .bottom) { if let id = selected, let n = map.node(id) { DetailCard(node: n, map: map, close: { selected = nil }) } }
                .overlay(alignment: .bottomLeading) { if selected == nil { Legend().padding(.horizontal, 12).padding(.bottom, 2) } }
            }
            .padding(.vertical, 8)
        }
    }

    private func dimmed(_ n: StackNode, _ map: StackMap) -> Bool {
        guard let s = selected, s != n.id else { return false }
        return !map.edges.contains { ($0.from == s && $0.to == n.id) || ($0.to == s && $0.from == n.id) }
    }

    private func draw(edge e: StackEdge, in ctx: inout GraphicsContext, layout: Layout, map: StackMap) {
        guard let a = layout.point[e.from], let b = layout.point[e.to] else { return }
        let w = layout.nodeW / 2
        let forward = b.x > a.x
        let start = CGPoint(x: forward ? a.x + w : a.x, y: forward ? a.y : a.y + 20)
        let end = CGPoint(x: forward ? b.x - w : b.x, y: forward ? b.y : b.y + 20)
        var path = Path()
        path.move(to: start)
        let dx = max(abs(end.x - start.x) * 0.5, 24)
        let c1 = CGPoint(x: start.x + (forward ? dx : 0), y: start.y + (forward ? 0 : 36))
        let c2 = CGPoint(x: end.x - (forward ? dx : 0), y: end.y + (forward ? 0 : 36))
        path.addCurve(to: end, control1: c1, control2: c2)

        let target = map.node(e.to)
        let failing = e.broken || (target?.status ?? 0) >= 500
        let involved = selected == nil || selected == e.from || selected == e.to
        let color: Color = failing ? Brand.alert : (e.configured ? Color.secondary : Brand.primaryText)
        let style = StrokeStyle(lineWidth: e.configured ? 1.3 : 1.8, lineCap: .round, dash: e.configured ? [4, 4] : [])
        ctx.stroke(path, with: .color(color.opacity(involved ? (e.configured ? 0.75 : 0.85) : 0.18)), style: style)

        // arrowhead
        let ang = atan2(end.y - c2.y, end.x - c2.x)
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - 7 * cos(ang - 0.45), y: end.y - 7 * sin(ang - 0.45)))
        head.addLine(to: CGPoint(x: end.x - 7 * cos(ang + 0.45), y: end.y - 7 * sin(ang + 0.45)))
        head.closeSubpath()
        ctx.fill(head, with: .color(color.opacity(involved ? 0.9 : 0.2)))
    }

    /// Columns by dependency depth; rows ordered by project, then port. Servers with no links sit in a strip at the bottom.
    struct Layout {
        var point: [String: CGPoint] = [:]
        var isolated: [StackNode] = []
        var nodeW: CGFloat = 120

        init(map: StackMap, size: CGSize, stripHeight: CGFloat) {
            let linked = Set(map.edges.flatMap { [$0.from, $0.to] })
            let connected = map.nodes.filter { linked.contains($0.id) }
            isolated = map.nodes.filter { !linked.contains($0.id) && $0.role != .missing }
            let layers = map.layers()
            let cols = max((connected.compactMap { layers[$0.id] }.max() ?? 0) + 1, 1)
            let colW = size.width / CGFloat(cols)
            nodeW = min(132, colW - 22)
            let top: CGFloat = 26
            let bottom = isolated.isEmpty ? 14 : stripHeight + 26
            let height = max(size.height - top - bottom, 60)
            let lists: [[StackNode]] = (0..<cols).map { c in
                connected.filter { layers[$0.id] == c }.sorted { ($0.project ?? "~", $0.port ?? 0) < ($1.project ?? "~", $1.port ?? 0) }
            }
            let rowGap = min(62, height / CGFloat(max(lists.map(\.count).max() ?? 1, 1)))
            let mid = top + height / 2
            var y: [String: CGFloat] = [:]

            for c in 0..<cols {
                var list = lists[c]
                if c == 0 {
                    for (i, n) in list.enumerated() { y[n.id] = mid + (CGFloat(i) - CGFloat(list.count - 1) / 2) * rowGap }
                } else {
                    // Sit each node level with the nodes it is linked to, so lines stay short and cross less.
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
            let perRow = max(Int(size.width / (nodeW + 10)), 1)
            for (i, n) in isolated.enumerated() {
                let row = i / perRow, col = i % perRow
                point[n.id] = CGPoint(x: 14 + nodeW / 2 + CGFloat(col) * (nodeW + 10), y: size.height - stripHeight / 2 - CGFloat(row) * 46 + 2)
            }
        }
    }
}

private struct NodeView: View {
    @EnvironmentObject var store: Store
    let node: StackNode
    let map: StackMap
    let selected: Bool
    let dimmed: Bool
    let width: CGFloat

    private var failing: Bool { node.role == .missing || (node.status ?? 0) >= 500 }

    var body: some View {
        let tint: Color = failing ? Brand.alert : (node.role == .client ? Color.secondary : Brand.mint)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(node.port.map { String($0) } ?? "worker").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            Text(node.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: 40, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.flat ? Color.primary.opacity(0.08) : Color.primary.opacity(0.07))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Brand.primary : (failing ? Brand.alert.opacity(0.7) : Color.primary.opacity(0.14)),
                              style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: node.role == .missing ? [3, 3] : []))
        }
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(Rectangle())
        .tip(summary)
    }

    private var summary: String {
        var lines = ["\(node.title)\(node.port.map { " :\($0)" } ?? "")" + (node.project.map { "  ·  \($0)" } ?? "")]
        let uses = map.uses(node.id), by = map.usedBy(node.id)
        if !uses.isEmpty { lines.append("Uses: " + uses.map { "\($0.title) :\($0.port ?? 0)" }.joined(separator: ", ")) }
        if !by.isEmpty { lines.append("Used by: " + by.map { "\($0.title)\($0.port.map { " :\($0)" } ?? "")" }.joined(separator: ", ")) }
        for b in map.brokenLinks(node.id) { lines.append("Expects :\(b.to.split(separator: ":").last ?? "") (\(b.hint ?? "config")), but nothing is listening") }
        if uses.isEmpty && by.isEmpty && map.brokenLinks(node.id).isEmpty { lines.append("No links found") }
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
        let by = map.usedBy(node.id), uses = map.uses(node.id), broken = map.brokenLinks(node.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(node.title)\(node.port.map { " :\($0)" } ?? "")").font(.system(size: 13, weight: .semibold))
                if let p = node.project { Text(p).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { close() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            if !by.isEmpty { Text("Used by " + names(by)).font(.caption).foregroundStyle(.secondary) }
            if !uses.isEmpty { Text("Uses " + names(uses)).font(.caption).foregroundStyle(.secondary) }
            ForEach(broken, id: \.to) { b in
                Label("Expects :\(b.to.split(separator: ":").last ?? "") (\(b.hint ?? "config")), but nothing is listening", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Brand.alert)
            }
            if let e = entry {
                HStack(spacing: 8) {
                    if e.web == .page { Button("Open") { store.open(e) }.buttonStyle(PillButton(tone: .open, width: 64)) }
                    else { Button(e.copyLabel) { store.copyLocal(e) }.buttonStyle(PillButton(tone: .quiet, width: 84)) }
                    Button("Stop") { store.kill(e) }.buttonStyle(PillButton(tone: .stop, width: 64))
                    if !by.isEmpty { Text("Stopping it affects \(by.count)").font(.caption).foregroundStyle(.secondary) }
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
            item(Brand.primaryText, dash: false, "connected now")
            item(Color.secondary, dash: true, "set in .env")
            item(Brand.alert, dash: false, "problem")
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
