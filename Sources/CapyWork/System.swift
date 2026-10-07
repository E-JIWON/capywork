import AppKit
import Carbon

enum HotKey {
    nonisolated(unsafe) private static var action: (@MainActor () -> Void)?

    /// ⌃⌥⌘C from anywhere. Carbon hot keys need no Accessibility permission.
    static func register(_ handler: @escaping @MainActor () -> Void) {
        action = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(controlKey | optionKey | cmdKey),
                            EventHotKeyID(signature: OSType(0x4341_5059), id: 1), GetApplicationEventTarget(), 0, &ref)
    }
}

enum Notifier {
    static func post(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \(quoted(body)) with title \(quoted(title)) sound name \"Glass\""]
        try? process.run()
    }

    /// AppleScript string literal. Session titles can contain quotes and backslashes.
    static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
