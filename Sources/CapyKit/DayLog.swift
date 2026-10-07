import Foundation

/// One day of hook events (see hook.sh) folded into session states and totals.
public struct DayLog: Sendable {
    public var sessions: [Session] = []
    public var firstEvent: Date?
    public var prompts = 0
    public var workTime: TimeInterval = 0
    public var ended: [(id: String, at: Date)] = []

    public init() {}

    /// Sessions killed without a SessionEnd would linger forever; drop them after this much silence.
    static let staleAfter: TimeInterval = 3 * 3600

    public static func load(_ day: Date, now: Date) -> DayLog {
        parse((try? String(contentsOf: Paths.log(for: day), encoding: .utf8)) ?? "", now: now)
    }

    public static func parse(_ text: String, now: Date) -> DayLog {
        var log = DayLog()
        var sessions: [String: Session] = [:]
        var workStart: [String: Date] = [:]

        func clockOff(_ id: String, _ t: Date) {
            if let start = workStart.removeValue(forKey: id) { log.workTime += t.timeIntervalSince(start) }
        }

        for line in text.split(separator: "\n") {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let ts = o["ts"] as? Double, let event = o["e"] as? String, let id = o["sid"] as? String
            else { continue }
            let t = Date(timeIntervalSince1970: ts)
            log.firstEvent = log.firstEvent ?? t
            var s = sessions[id] ?? Session(id: id, project: projectName(o["cwd"] as? String), since: t, lastEvent: t)
            let before = s.state

            switch event {
            case "UserPromptSubmit":
                log.prompts += 1
                s.state = .working
                s.finishedAt = nil
                s.failStreak = 0
                let prompt = (o["prompt"] as? String ?? "").replacingOccurrences(of: "\n", with: " ")
                if !prompt.hasPrefix("<") { s.task = prompt }  // skip system turns like <task-notification>
                workStart[id] = workStart[id] ?? t
            case "PostToolUse", "PostToolUseFailure":
                s.state = .working
                s.failStreak = event == "PostToolUse" ? 0 : s.failStreak + 1
                workStart[id] = workStart[id] ?? t
            case "Notification":
                // The 60s "waiting for your input" ping is just idle; only permission prompts wait on you.
                if (o["msg"] as? String ?? "").contains("permission") { s.state = .waiting }
            case "Stop":
                s.state = .idle
                s.finishedAt = t
                clockOff(id, t)
            case "SessionEnd":
                clockOff(id, t)
                if sessions.removeValue(forKey: id) != nil { log.ended.append((id, t)) }
                continue
            default:
                break
            }
            if s.state != before { s.since = t }
            s.lastEvent = t
            sessions[id] = s
        }

        for (id, start) in workStart where sessions[id] != nil { log.workTime += now.timeIntervalSince(start) }
        log.sessions = sessions.values
            .filter { now.timeIntervalSince($0.lastEvent) < staleAfter }
            .sorted(by: Session.byUrgency)
        return log
    }

    static func projectName(_ cwd: String?) -> String {
        guard let cwd else { return "?" }
        if cwd.contains("/scratch-workspaces/") { return "임시 작업" }
        return cwd.split(separator: "/").last.map(String.init) ?? "?"
    }
}
