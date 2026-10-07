import Foundation

public struct UsageWindow: Sendable, Equatable {
    public var percent: Double
    public var resetsAt: Date?
    /// The reset time was inferred from usage history rather than reported.
    public var estimated: Bool

    public init(percent: Double, resetsAt: Date?, estimated: Bool = false) {
        self.percent = percent
        self.resetsAt = resetsAt
        self.estimated = estimated
    }
}

/// Plan limits without logging in. Claude Code's statusLine `rate_limits` (saved by statusline.sh)
/// reports reset times; the Claude app's ~15-min usage samples don't, so resets are inferred from
/// where the percentages drop to zero. The newest percentage wins.
public struct PlanUsage: Sendable, Equatable {
    public enum Source: Sendable, Equatable { case account, local }

    public var fiveHour: UsageWindow?
    public var weekly: UsageWindow?
    public var source = Source.local
    /// When the numbers were measured.
    public var asOf: Date?

    public init(fiveHour: UsageWindow? = nil, weekly: UsageWindow? = nil, source: Source = .local, asOf: Date? = nil) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.source = source
        self.asOf = asOf
    }

    /// The `/api/oauth/usage` response: exact percentages and reset times for the signed-in account.
    public static func fromAccount(_ data: Data, at now: Date) -> PlanUsage? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func window(_ key: String) -> UsageWindow? {
            guard let w = o[key] as? [String: Any], let pct = (w["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return UsageWindow(percent: pct, resetsAt: (w["resets_at"] as? String).flatMap(isoDate))
        }
        let usage = PlanUsage(fiveHour: window("five_hour"), weekly: window("seven_day"), source: .account, asOf: now)
        return usage.isEmpty ? nil : usage
    }

    static func isoDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    public var isEmpty: Bool { fiveHour == nil && weekly == nil }

    public static func read(statusLine: URL = Paths.statusLineSnapshot,
                            appHistory: URL = Paths.planUsageHistory, now: Date) -> PlanUsage {
        var usage = PlanUsage()
        var snapshotAt = Date.distantPast

        if let o = json(statusLine), let ts = o["ts"] as? Double, let limits = o["rate_limits"] as? [String: Any] {
            snapshotAt = Date(timeIntervalSince1970: ts)
            usage.asOf = snapshotAt
            usage.fiveHour = window(limits["five_hour"], now: now)
            usage.weekly = window(limits["seven_day"], now: now)
        }

        let samples = Sample.read(appHistory)
        if let last = samples.last, last.at > snapshotAt {
            usage.asOf = last.at
            usage.fiveHour = UsageWindow(percent: last.fiveHour, resetsAt: usage.fiveHour?.resetsAt)
            usage.weekly = UsageWindow(percent: last.weekly, resetsAt: usage.weekly?.resetsAt)
        }
        if usage.fiveHour?.resetsAt == nil, let r = Sample.nextFiveHourReset(samples, now: now) {
            usage.fiveHour?.resetsAt = r
            usage.fiveHour?.estimated = true
        }
        if usage.weekly?.resetsAt == nil, let r = Sample.nextWeeklyReset(samples, now: now) {
            usage.weekly?.resetsAt = r
            usage.weekly?.estimated = true
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

/// One Claude-app usage sample. Limits reset on the hour, which keeps the estimates sharp.
struct Sample {
    let at: Date
    let fiveHour: Double
    let weekly: Double

    static let fiveHours: TimeInterval = 5 * 3600
    static let week: TimeInterval = 7 * 86400

    static func read(_ url: URL) -> [Sample] {
        guard let raw = PlanUsage.json(url)?["samples"] as? [[String: Any]] else { return [] }
        return raw.compactMap { s in
            guard let t = s["t"] as? Double, let u = s["u"] as? [String: Double] else { return nil }
            return Sample(at: Date(timeIntervalSince1970: t / 1000), fiveHour: u["fh"] ?? 0, weekly: u["sd"] ?? 0)
        }
    }

    /// The window opens with the first use after the last reset (a zero, or a drop when the app
    /// missed the zero) and closes five hours after that hour.
    static func nextFiveHourReset(_ samples: [Sample], now: Date) -> Date? {
        guard let last = samples.last, last.fiveHour > 0 else { return nil }
        let pairs = zip(samples, samples.dropFirst())
        guard let (a, b) = pairs.reversed().first(where: { a, b in
            b.fiveHour > 0 && (a.fiveHour == 0 || b.fiveHour < a.fiveHour - 0.5)
        }) else { return nil }
        guard b.at.timeIntervalSince(a.at) < 3600 else { return nil }  // app was off; too vague
        let reset = hourFloor(midpoint((a.at, b.at))) + fiveHours
        return reset > now ? reset : nil
    }

    /// Weekly resets land at the same time each week, so overlapping past drops (taken modulo a
    /// week) pins the time down even when the app was off for some of them. A one-off reset (a plan
    /// change, a global reset) doesn't fit the others; the schedule backed by the most drops wins,
    /// and on a tie the newer one.
    static func nextWeeklyReset(_ samples: [Sample], now: Date) -> Date? {
        let drops = zip(samples, samples.dropFirst())
            .filter { a, b in b.weekly < a.weekly - 3 || (b.weekly == 0 && a.weekly > 0) }
            .map { ($0.at, $1.at) }
        var best: (support: Int, lo: Date, hi: Date)?
        for (lo0, hi0) in drops.reversed() {
            var (lo, hi, support) = (lo0, hi0, 0)
            for (a, b) in drops {
                let shift = (lo.timeIntervalSince(a) / week).rounded() * week
                let (nlo, nhi) = (max(lo, a + shift), min(hi, b + shift))
                if nlo <= nhi { (lo, hi, support) = (nlo, nhi, support + 1) }
            }
            if support > best?.support ?? 0 { best = (support, lo, hi) }
        }
        guard let best, best.hi.timeIntervalSince(best.lo) <= 2 * 3600 else { return nil }
        var reset = hourRound(midpoint((best.lo, best.hi)))
        while reset <= now { reset += week }
        return reset
    }

    static func midpoint(_ r: (Date, Date)) -> Date { r.0 + r.1.timeIntervalSince(r.0) / 2 }
    static func hourFloor(_ d: Date) -> Date { Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 3600).rounded(.down) * 3600) }
    static func hourRound(_ d: Date) -> Date { Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 3600).rounded() * 3600) }
}
