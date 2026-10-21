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
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
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
        popover.delegate = self
        // An explicit vibrancy view, so the blur does not depend on popover defaults.
        let host = NSHostingController(rootView: RootView().environmentObject(store))
        host.sizingOptions = []
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        let vc = NSViewController()
        vc.view = effect
        vc.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: effect.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: effect.topAnchor), host.view.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        popover.contentSize = NSHostingView(rootView: RootView().environmentObject(store)).fittingSize
        popover.contentViewController = vc

        store.$entries.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTitle() }.store(in: &bag)
        updateTitle()

        if CommandLine.arguments.contains("--show") {   // debug: open the popover at launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.toggle() }
        }

        // ⌘O / ⌘C / ⌘R / ⌘L / ⌘⌫ act on the row under the pointer.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self, self.popover.isShown,
                  ev.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return ev }
            if let tv = self.popover.contentViewController?.view.window?.firstResponder as? NSTextView, tv.selectedRange().length > 0 {
                return ev   // let ⌘C copy selected text in the filter box
            }
            let ch = ev.charactersIgnoringModifiers?.lowercased() ?? ""
            let handled = MainActor.assumeIsolated { self.store.shortcut(ch, deleteKey: ev.keyCode == 51) }
            return handled ? nil : ev
        }

        hotKey = HotKey(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey) { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.toggle() } }
        }
    }

    func popoverDidClose(_ notification: Notification) { TipWindow.shared.hide() }

    private func updateTitle() {
        let n = store.count
        item.button?.image = IconArt.menuBar(active: n > 0)
        item.button?.title = n > 0 ? " \(n)" : ""
        item.button?.setAccessibilityLabel("LocalServer, \(n) running")
    }

    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let b = item.button else { return }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        store.refreshBackdrop(screen: b.window?.screen, dark: dark)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NotificationCenter.default.post(name: .popoverDidShow, object: nil)
        Task { await store.refresh() }
    }
}
