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
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        store.onCastChange = { [weak self] in self?.render($0) }
        render(store.cast)
        #if DEBUG
        if let dir = ProcessInfo.processInfo.environment["CAPYWORK_SELFCHECK"] { selfCheck(into: URL(filePath: dir)) }
        #endif
    }

    private func render(_ cast: Cast) {
        item.button?.image = MenuBarIcon.image(for: cast)
        item.button?.setAccessibilityLabel(store.summary)
    }

    /// Click opens the panel; right-click (or ⌃-click) jumps straight to the session that needs you.
    @objc private func clicked() {
        let event = NSApp.currentEvent
        handleClick(secondary: event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true)
    }

    private func handleClick(secondary: Bool) {
        if secondary {
            popover.performClose(nil)
            store.openMostUrgent()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    #if DEBUG
    /// `CAPYWORK_SELFCHECK=<dir>`: click the real status button like a user, snapshot the panel,
    /// right-click, write report.json, quit. Lets QA cover the AppKit wiring without screen access.
    private func selfCheck(into dir: URL) {
        var report: [String: Any] = [:]
        var opened: [String] = []
        store.openURL = { opened.append($0.absoluteString) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func save(_ view: NSView?, _ name: String) {
            guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appending(path: name))
        }
        func after(_ delay: Double, _ step: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(step) }
        }

        after(1.5) { [self] in
            save(item.button, "statusitem.png")
            report["statusItemImage"] = item.button?.image != nil
            report["accessibilityLabel"] = item.button?.accessibilityLabel()
            item.button?.performClick(nil)
            after(1) { [self] in
                report["panelOpensOnClick"] = popover.isShown
                save(popover.contentViewController?.view.window?.contentView?.superview, "panel.png")  // includes the popover material
                item.button?.performClick(nil)
                after(1) { [self] in
                    report["panelClosesOnSecondClick"] = !popover.isShown
                    handleClick(secondary: true)
                    report["rightClickOpens"] = opened
                    report["panelStaysClosedOnRightClick"] = !popover.isShown
                    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                        try? data.write(to: dir.appending(path: "report.json"))
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }
    #endif
}
