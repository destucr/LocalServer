import AppKit
import CoreImage
import UserNotifications

/// Editors and terminals we can open a project in.
enum Editors {
    private static let known: [(name: String, bundleID: String)] = [
        ("Cursor", "com.todesktop.230313mzl4w4u92"), ("VS Code", "com.microsoft.VSCode"), ("Windsurf", "com.exafunction.windsurf"),
        ("Zed", "dev.zed.Zed"), ("Sublime Text", "com.sublimetext.4"), ("PhpStorm", "com.jetbrains.PhpStorm"),
        ("WebStorm", "com.jetbrains.WebStorm"), ("Xcode", "com.apple.dt.Xcode"),
    ]

    static let installed: [(name: String, url: URL)] = known.compactMap { k in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: k.bundleID).map { (k.name, $0) }
    }

    static func open(_ path: String, with app: URL) {
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func openTerminal(at path: String) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}

enum QR {
    static func image(_ text: String, size: CGFloat = 220) -> NSImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage else { return nil }
        let scale = size / out.extent.width
        let scaled = out.transformed(by: CGAffineTransform(scaleX: scale.rounded(.down), y: scale.rounded(.down)))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }
}

/// Small native dialogs. The popover closes when one opens, which is fine for one-off questions.
@MainActor
enum Dialogs {
    static func confirm(_ title: String, _ message: String, ok: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.alertStyle = .warning
        a.addButton(withTitle: ok)
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    /// Returns the new text, "" to reset, or nil if cancelled.
    static func prompt(_ title: String, _ message: String, value: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        a.accessoryView = field
        a.window.initialFirstResponder = field
        return a.runModal() == .alertFirstButtonReturn ? field.stringValue.trimmingCharacters(in: .whitespaces) : nil
    }

    /// Shows a QR code. Returns true if the user chose to copy the link.
    static func qr(title: String, url: String, note: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = "\(url)\n\n\(note)"
        a.addButton(withTitle: "Copy link")
        a.addButton(withTitle: "Done")
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 220, height: 220))
        view.image = QR.image(url)
        a.accessoryView = view
        return a.runModal() == .alertFirstButtonReturn
    }
}

enum Notifier {
    private static var available: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard available else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
