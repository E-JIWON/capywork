import Foundation

/// The Claude desktop app keeps one JSON per Code session, linking its id to the CLI session id.
/// Read-only; an app update may change the format, in which case titles and links just go missing.
public struct DesktopSession: Sendable {
    public let cliID: String
    public let id: String
    public let title: String
    public let file: URL
    public let modified: Date
    public let lastFocused: Date

    public static func openURL(for id: String) -> URL? {
        URL(string: "claude://code/continue?session=\(id)")
    }

    public static let bundleID = "com.anthropic.claudefordesktop"

    public static func read(_ file: URL) -> DesktopSession? {
        guard let data = try? Data(contentsOf: file),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cliID = o["cliSessionId"] as? String, let id = o["sessionId"] as? String,
              let modified = modificationDate(file)
        else { return nil }
        return DesktopSession(cliID: cliID, id: id, title: o["title"] as? String ?? "", file: file,
                              modified: modified,
                              lastFocused: Date(timeIntervalSince1970: ((o["lastFocusedAt"] as? Double) ?? 0) / 1000))
    }

    public static func scan(_ root: URL = Paths.desktopSessions) -> [DesktopSession] {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { item in
            guard let url = item as? URL, url.lastPathComponent.hasPrefix("local_"), url.pathExtension == "json"
            else { return nil }
            return read(url)
        }
    }

    public static func modificationDate(_ file: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }
}
