import AppKit
import SwiftUI

/// A small tooltip bubble drawn in its own window next to the pointer.
/// System tooltips often stay hidden in a menu bar popover, and a parent's tooltip can hide a child's, so we draw our own.
@MainActor
final class TipWindow {
    static let shared = TipWindow()

    private let panel: NSPanel
    private let label = NSTextField(wrappingLabelWithString: "")
    private var pending: DispatchWorkItem?

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let bubble = NSVisualEffectView()
        bubble.material = .toolTip
        bubble.blendingMode = .behindWindow
        bubble.state = .active
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 7
        bubble.layer?.masksToBounds = true
        bubble.layer?.borderWidth = 0.5
        bubble.layer?.borderColor = NSColor.separatorColor.cgColor

        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 5
        label.preferredMaxLayoutWidth = 300
        bubble.addSubview(label)
        panel.contentView = bubble
    }

    func show(_ text: String, delay: Double = 0.3) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.present(text) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hide() {
        pending?.cancel()
        panel.orderOut(nil)
    }

    private func present(_ text: String) {
        label.stringValue = text
        let size = label.fittingSize
        let padX: CGFloat = 10, padY: CGFloat = 6
        let w = ceil(size.width) + padX * 2, h = ceil(size.height) + padY * 2
        label.frame = NSRect(x: padX, y: padY, width: ceil(size.width), height: ceil(size.height))

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var origin = NSPoint(x: mouse.x - w / 2 + 6, y: mouse.y - h - 24)   // below the pointer
        if let vis = screen?.visibleFrame {
            origin.x = min(max(origin.x, vis.minX + 6), vis.maxX - w - 6)
            if origin.y < vis.minY + 6 { origin.y = mouse.y + 22 }          // no room below: go above
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: true)
        panel.orderFrontRegardless()
    }
}

private struct TipModifier: ViewModifier {
    let text: String
    func body(content: Content) -> some View {
        content
            .onHover { $0 ? TipWindow.shared.show(text) : TipWindow.shared.hide() }
            .onDisappear { TipWindow.shared.hide() }
    }
}

extension View {
    /// Plain tooltip.
    func tip(_ text: String) -> some View { modifier(TipModifier(text: text)) }
}
