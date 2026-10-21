import AppKit

/// Works out how much extra tint the popover needs so text stays readable over whatever wallpaper is behind it.
/// The popover is translucent, so a bright wallpaper under a dark popover (or the reverse) would wash text out.
enum Backdrop {
    // What the system material alone roughly gives us (measured against reference screenshots).
    private static let baseAlpha = (light: 0.66, dark: 0.62)
    private static let tintGray = (light: 1.0, dark: 0.10)

    private static var cache: [String: Double] = [:]

    // MARK: Contrast math (WCAG)

    private static func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func lum(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) }
    static func ratio(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }

    /// Smallest extra tint (0...0.9) that keeps secondary text and link text at 4.5:1 over a wallpaper of gray level `wall`.
    static func extraTint(wall: Double, dark: Bool) -> Double {
        let base = dark ? baseAlpha.dark : baseAlpha.light
        let t = dark ? tintGray.dark : tintGray.light
        let label = dark ? 1.0 : 0.0
        let link = dark ? lum(0.65, 0.67, 0.99) : lum(0.22, 0.18, 0.72)
        var e = 0.0
        while e <= 0.9 {
            let total = 1 - (1 - base) * (1 - e)
            let bg = t * total + wall * (1 - total)
            let bgL = lum(bg, bg, bg)
            let secondary = label * 0.55 + bg * 0.45
            if ratio(lum(secondary, secondary, secondary), bgL) >= 4.6, ratio(link, bgL) >= 4.5 { return e }
            e += 0.02
        }
        return 0.9
    }

    // MARK: Wallpaper sampling

    /// Gray level (sRGB, 0...1) of the part of the wallpaper the popover covers. Worst case: the darkest block for a light
    /// popover, the brightest for a dark one. Needs no permission: it reads the wallpaper file, not the screen.
    static func wallpaperGray(screen: NSScreen?, dark: Bool) -> Double? {
        guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        let key = url.path + (dark ? "|d" : "|l")
        if let hit = cache[key] { return hit }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 96,
                  kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { p in
            CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        // The popover hangs from the menu bar near the right edge: top 60%, right 40% of the picture, in a 4x4 grid of blocks.
        let x0 = Int(Double(w) * 0.60), x1 = w, y0 = 0, y1 = Int(Double(h) * 0.60)   // row 0 is the top
        var blocks: [Double] = []
        for by in 0..<4 { for bx in 0..<4 {
            var sum = 0.0, n = 0.0
            for y in (y0 + (y1 - y0) * by / 4)..<(y0 + (y1 - y0) * (by + 1) / 4) {
                for x in (x0 + (x1 - x0) * bx / 4)..<(x0 + (x1 - x0) * (bx + 1) / 4) {
                    let i = (y * w + x) * 4
                    sum += (0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])) / 255
                    n += 1
                }
            }
            if n > 0 { blocks.append(sum / n) }
        } }
        guard let worst = dark ? blocks.max() : blocks.min() else { return nil }
        cache[key] = worst
        return worst
    }

    static func tint(screen: NSScreen?, dark: Bool) -> Double {
        guard let g = wallpaperGray(screen: screen, dark: dark) else { return 0.12 }   // unknown wallpaper: a little margin
        return extraTint(wall: g, dark: dark)
    }

    static var tintColor: (light: NSColor, dark: NSColor) { (NSColor(white: tintGray.light, alpha: 1), NSColor(white: tintGray.dark, alpha: 1)) }

    /// `LocalServer --contrast`: prints the tint chosen for a few wallpapers.
    static func report() {
        for dark in [false, true] {
            print(dark ? "dark popover" : "light popover")
            for (name, g) in [("black wallpaper", 0.0), ("dark grey", 0.25), ("mid grey", 0.5), ("light grey", 0.75), ("white wallpaper", 1.0)] {
                let e = extraTint(wall: g, dark: dark)
                let base = dark ? baseAlpha.dark : baseAlpha.light
                let total = 1 - (1 - base) * (1 - e)
                let t = dark ? tintGray.dark : tintGray.light
                let bg = t * total + g * (1 - total)
                let label = dark ? 1.0 : 0.0
                let sec = label * 0.55 + bg * 0.45
                print(String(format: "  %-16@ extra tint %.2f   secondary text %.2f:1", name as NSString, e, ratio(lum(sec, sec, sec), lum(bg, bg, bg))))
            }
        }
    }
}
