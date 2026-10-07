import Foundation

public enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// `CAPYWORK_HOME` points a second copy at a sandbox log (used for QA).
    public static var root: URL {
        ProcessInfo.processInfo.environment["CAPYWORK_HOME"].map { URL(filePath: $0) } ?? home.appending(path: ".capywork")
    }
    public static var backfill: URL { root.appending(path: "backfill.json") }
    public static var statusLineSnapshot: URL { root.appending(path: "limits.json") }

    public static let claudeApp = home.appending(path: "Library/Application Support/Claude")
    public static let desktopSessions = claudeApp.appending(path: "claude-code-sessions")
    public static let planUsageHistory = claudeApp.appending(path: "plan-usage-history.json")

    /// Local-time day, matching `date +%F` in hook.sh.
    public static func log(for day: Date) -> URL {
        root.appending(path: "log/\(dayKey(day)).jsonl")
    }

    public static func dayKey(_ day: Date) -> String {
        day.formatted(dayFormat)
    }

    static let dayFormat = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
}
