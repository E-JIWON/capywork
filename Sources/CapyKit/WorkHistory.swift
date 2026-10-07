import Foundation

/// Daily work time: hook logs for the past week, backfill.json (built from transcripts) before that.
public enum WorkHistory {
    public static func load(today: Date, backfill: URL = Paths.backfill) -> [Date: TimeInterval] {
        let cal = Calendar.current
        var days = readBackfill(backfill)
        for offset in 1..<7 {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let worked = DayLog.load(day, now: cal.date(byAdding: .day, value: 1, to: day)!).workTime
            if worked > 0 { days[day] = max(days[day] ?? 0, worked) }
        }
        return days
    }

    /// Hook logs are only read for the past week; anything older than `keep` days is deleted.
    public static func pruneLogs(today: Date, keep: Int = 30, dir: URL = Paths.root.appending(path: "log")) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -keep, to: today),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where name.hasSuffix(".jsonl") {
            if let day = try? Paths.dayFormat.parse(String(name.dropLast(6))), day < cutoff {
                try? FileManager.default.removeItem(at: dir.appending(path: name))
            }
        }
    }

    public static func readBackfill(_ url: URL) -> [Date: TimeInterval] {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Double]
        else { return [:] }
        let cal = Calendar.current
        return raw.reduce(into: [:]) { out, entry in
            if let day = try? Paths.dayFormat.parse(entry.key) { out[cal.startOfDay(for: day)] = entry.value }
        }
    }

    public static func week(containing day: Date) -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: day)
        let monday = cal.date(byAdding: .day, value: -((cal.component(.weekday, from: today) + 5) % 7), to: today)!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
    }
}
