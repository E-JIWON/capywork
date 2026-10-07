import AppKit
import CapyKit
import SwiftUI

@main
struct CapyWorkApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// A plain NSStatusItem: swapping its image per frame is far cheaper than
/// having MenuBarExtra re-snapshot a SwiftUI label.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SessionStore()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: SessionPanel(store: store))
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        store.onCastChange = { [weak self] in self?.render($0) }
        render(store.cast)
    }

    private func render(_ cast: Cast) {
        item.button?.image = MenuBarIcon.image(for: cast)
        item.button?.setAccessibilityLabel(store.summary)
    }

    @objc private func togglePanel() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
