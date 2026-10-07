import Foundation

/// One day of hook events (see hook.sh) folded into session states and totals.
public struct DayLog: Sendable {
    public var sessions: [Session] = []
    public var firstEvent: Date?
    public var prompts = 0
    public var workTime: TimeInterval = 0
    public var ended: [(id: String, at: Date)] = []

    public init() {}

    public static func load(_ day: Date, now: Date) -> DayLog {
        parse((try? String(contentsOf: Paths.log(for: day), encoding: .utf8)) ?? "", now: now)
    }

    public static func parse(_ text: String, now: Date) -> DayLog {
        var fold = Fold()
        for line in text.split(separator: "\n") { fold.apply(line) }
        return fold.snapshot(now: now)
    }

    /// Running state of the fold, so a growing log can be read a few new lines at a time.
    struct Fold {
        var log = DayLog()
        var sessions: [String: Session] = [:]
        var workStart: [String: Date] = [:]

        /// Sessions killed without a SessionEnd would linger forever; drop them after this much silence.
        static let staleAfter: TimeInterval = 3 * 3600
        /// Interrupting a turn (Esc) sends no Stop, so "working" with this much silence has really stopped.
        static let stallAfter: TimeInterval = 10 * 60

        mutating func apply(_ line: Substring) {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let ts = o["ts"] as? Double, let event = o["e"] as? String, let id = o["sid"] as? String
            else { return }
            let t = Date(timeIntervalSince1970: ts)
            log.firstEvent = log.firstEvent ?? t
            var s = sessions[id] ?? Session(id: id, project: DayLog.projectName(o["cwd"] as? String), since: t, lastEvent: t)
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
                // Only permission prompts wait on you; the "waiting for your input" ping means the turn is over.
                if (o["msg"] as? String ?? "").contains("permission") { s.state = .waiting }
                else if s.state == .working { s.state = .idle }
            case "Stop":
                s.state = .idle
                s.finishedAt = t
                clockOff(id, t)
            case "SessionEnd":
                clockOff(id, t)
                if sessions.removeValue(forKey: id) != nil { log.ended.append((id, t)) }
                return
            default:
                break
            }
            if s.state != before { s.since = t }
            s.lastEvent = t
            sessions[id] = s
        }

        mutating func clockOff(_ id: String, _ t: Date) {
            if let start = workStart.removeValue(forKey: id) { log.workTime += t.timeIntervalSince(start) }
        }

        func snapshot(now: Date) -> DayLog {
            var out = log
            var sessions = sessions
            for (id, start) in workStart {
                guard let s = sessions[id] else { continue }
                let stalled = now.timeIntervalSince(s.lastEvent) > Self.stallAfter
                out.workTime += (stalled ? s.lastEvent : now).timeIntervalSince(start)
                if stalled && s.state == .working {
                    sessions[id]?.state = .idle
                    sessions[id]?.since = s.lastEvent
                }
            }
            out.sessions = sessions.values
                .filter { now.timeIntervalSince($0.lastEvent) < Self.staleAfter }
                .sorted(by: Session.byUrgency)
            return out
        }
    }

    static func projectName(_ cwd: String?) -> String {
        guard let cwd else { return "?" }
        if cwd.contains("/scratch-workspaces/") { return "임시 작업" }
        return cwd.split(separator: "/").last.map(String.init) ?? "?"
    }
}

/// Follows today's log file, reading only the bytes appended since the last call.
public final class DayLogReader {
    private let file: (Date) -> URL
    private var day: Date?
    private var offset: UInt64 = 0
    private var partial = Data()
    private var fold = DayLog.Fold()

    public init(file: @escaping (Date) -> URL = Paths.log(for:)) {
        self.file = file
    }

    public func read(_ day: Date, now: Date) -> DayLog {
        if day != self.day { reset(day) }
        guard let handle = try? FileHandle(forReadingFrom: file(day)) else { return fold.snapshot(now: now) }
        defer { try? handle.close() }
        if let end = try? handle.seekToEnd(), end < offset { reset(day) }  // truncated or replaced
        try? handle.seek(toOffset: offset)
        let fresh = (try? handle.readToEnd()) ?? Data()
        offset += UInt64(fresh.count)

        var buffer = partial + fresh
        if let lastNewline = buffer.lastIndex(of: UInt8(ascii: "\n")) {
            let complete = buffer[..<lastNewline]
            for line in String(decoding: complete, as: UTF8.self).split(separator: "\n") { fold.apply(line) }
            buffer = Data(buffer[(lastNewline + 1)...])
        }
        partial = buffer  // a line the hook is still writing
        return fold.snapshot(now: now)
    }

    private func reset(_ day: Date) {
        self.day = day
        offset = 0
        partial = Data()
        fold = DayLog.Fold()
    }
}
