import AppKit
import SwiftUI

/// One glyph, drawn in code, used for the menu bar icon and the app icon: two stacked server units with status dots.
enum IconArt {
    private static func units(in r: NSRect) -> [NSRect] {
        let unitH = r.height * 0.34, gap = r.height * 0.10
        let y0 = r.midY - (2 * unitH + gap) / 2
        return [0, 1].map { i in NSRect(x: r.minX + r.width * 0.06, y: y0 + CGFloat(1 - i) * (unitH + gap), width: r.width * 0.88, height: unitH) }
    }

    static func drawGlyph(in r: NSRect, line: CGFloat, stroke: NSColor, fill: NSColor?, lit: [Bool], dot: NSColor, glow: Bool = false) {
        for (i, u) in units(in: r).enumerated() {
            let path = NSBezierPath(roundedRect: u, xRadius: u.height * 0.3, yRadius: u.height * 0.3)
            if let fill { fill.setFill(); path.fill() }
            stroke.setStroke(); path.lineWidth = line; path.stroke()

            let d = u.height * 0.30
            let c = NSRect(x: u.minX + u.height * 0.36, y: u.midY - d / 2, width: d, height: d)
            if lit[i] {
                NSGraphicsContext.saveGraphicsState()
                if glow {
                    let s = NSShadow(); s.shadowBlurRadius = u.height * 0.35; s.shadowColor = dot.withAlphaComponent(0.9); s.set()
                }
                dot.setFill(); NSBezierPath(ovalIn: c).fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                stroke.setStroke()
                let ring = NSBezierPath(ovalIn: c.insetBy(dx: line * 0.4, dy: line * 0.4)); ring.lineWidth = line * 0.8; ring.stroke()
            }
            let slot = NSBezierPath()
            slot.move(to: NSPoint(x: u.midX + u.width * 0.02, y: u.midY))
            slot.line(to: NSPoint(x: u.maxX - u.height * 0.36, y: u.midY))
            slot.lineWidth = line; slot.lineCapStyle = .round
            stroke.withAlphaComponent(stroke.alphaComponent * 0.55).setStroke(); slot.stroke()
        }
    }

    /// Menu bar icon. A template image, so the system tints it for light, dark and highlighted states.
    /// With nothing running the dots are hollow and the icon is dimmer.
    static func menuBar(active: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 19, height: 17), flipped: false) { rect in
            let c = NSColor.black.withAlphaComponent(active ? 1 : 0.55)
            drawGlyph(in: NSRect(x: 0, y: 0, width: 19, height: 17).insetBy(dx: 0.5, dy: 0), line: 1.3, stroke: c, fill: nil,
                      lit: [active, active], dot: c)
            return true
        }
        img.isTemplate = true
        return img
    }

    /// 1024 px app icon in the macOS icon grid (824 px squircle with a soft shadow).
    static func appIcon() -> NSBitmapImageRep {
        let s: CGFloat = 1024
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: s, height: s)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        let body = NSRect(x: 100, y: 100, width: 824, height: 824)
        let path = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowBlurRadius = 26; shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32); shadow.set()
        NSColor(red: 0.27, green: 0.22, blue: 0.80, alpha: 1).setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(colors: [NSColor(red: 0.43, green: 0.62, blue: 1.0, alpha: 1), NSColor(red: 0.27, green: 0.22, blue: 0.80, alpha: 1)])!
            .draw(in: body, angle: -90)
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
            .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        let g = NSRect(x: 252, y: 252, width: 520, height: 520)
        drawGlyph(in: g, line: 24, stroke: NSColor.white.withAlphaComponent(0.95), fill: NSColor.white.withAlphaComponent(0.14),
                  lit: [true, true], dot: NSColor(red: 0.36, green: 0.93, blue: 0.54, alpha: 1), glow: true)

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}

enum Motion {
    /// Animations are skipped when the system asks for reduced motion.
    static var anim: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .smooth(duration: 0.25)
    }
}
