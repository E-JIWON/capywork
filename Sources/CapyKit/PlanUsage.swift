import Foundation

public struct UsageWindow: Sendable, Equatable {
    public var percent: Double
    public var resetsAt: Date?

    public init(percent: Double, resetsAt: Date?) {
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

/// Plan limits without logging in: Claude Code's statusLine `rate_limits` (saved by statusline.sh)
/// has reset times; the Claude app's 15-min usage samples don't. The newest percentage wins.
public struct PlanUsage: Sendable, Equatable {
    public var fiveHour: UsageWindow?
    public var weekly: UsageWindow?

    public init(fiveHour: UsageWindow? = nil, weekly: UsageWindow? = nil) {
        self.fiveHour = fiveHour
        self.weekly = weekly
    }

    public var isEmpty: Bool { fiveHour == nil && weekly == nil }

    public static func read(statusLine: URL = Paths.statusLineSnapshot,
                            appHistory: URL = Paths.planUsageHistory, now: Date) -> PlanUsage {
        var usage = PlanUsage()
        var snapshotAt = Date.distantPast

        if let o = json(statusLine), let ts = o["ts"] as? Double, let limits = o["rate_limits"] as? [String: Any] {
            snapshotAt = Date(timeIntervalSince1970: ts)
            usage.fiveHour = window(limits["five_hour"], now: now)
            usage.weekly = window(limits["seven_day"], now: now)
        }

        if let o = json(appHistory),
           let last = (o["samples"] as? [[String: Any]])?.last,
           let t = last["t"] as? Double, let u = last["u"] as? [String: Double],
           Date(timeIntervalSince1970: t / 1000) > snapshotAt {
            if let fh = u["fh"] { usage.fiveHour = UsageWindow(percent: fh, resetsAt: usage.fiveHour?.resetsAt) }
            if let sd = u["sd"] { usage.weekly = UsageWindow(percent: sd, resetsAt: usage.weekly?.resetsAt) }
        }
        return usage
    }

    static func window(_ raw: Any?, now: Date) -> UsageWindow? {
        guard let w = raw as? [String: Any], let pct = w["used_percentage"] as? Double else { return nil }
        let resets = (w["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
        if let resets, resets <= now { return UsageWindow(percent: 0, resetsAt: nil) }  // window rolled over
        return UsageWindow(percent: pct, resetsAt: resets)
    }

    static func json(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
