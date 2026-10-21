import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

extension Notification.Name {
    static let popoverDidShow = Notification.Name("LocalServer.popoverDidShow")
}

/// Global hotkey via Carbon (needs no accessibility permission).
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handler: (() -> Void)?

    init(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        Self.handler = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in HotKey.handler?(); return noErr }, 1, &spec, nil, nil)
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: 0x4C535256, id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shortcutLabel = "⌃⌥P"

    private let store = Store.shared
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var bag = Set<AnyCancellable>()
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            b.image = IconArt.menuBar(active: false)
            b.imagePosition = .imageLeading
            b.target = self
            b.action = #selector(toggle)
        }
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: RootView().environmentObject(store))

        store.$entries.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTitle() }.store(in: &bag)
        updateTitle()

        hotKey = HotKey(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey) { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.toggle() } }
        }
    }

    private func updateTitle() {
        let n = store.count
        item.button?.image = IconArt.menuBar(active: n > 0)
        item.button?.title = n > 0 ? " \(n)" : ""
        item.button?.setAccessibilityLabel("LocalServer, \(n) running")
    }

    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let b = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NotificationCenter.default.post(name: .popoverDidShow, object: nil)
        Task { await store.refresh() }
    }
}
