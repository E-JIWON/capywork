import Foundation
import Testing
@testable import CapyKit

private func at(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

private func event(_ ts: Int, _ e: String, _ sid: String, extra: String = "") -> String {
    #"{"ts":\#(ts),"e":"\#(e)","sid":"\#(sid)","cwd":"/x/\#(sid)"\#(extra)}"#
}

@Suite("DayLog")
struct DayLogTests {
    let log = [
        event(1000, "SessionStart", "a"),
        event(1010, "UserPromptSubmit", "a", extra: #","prompt":"fix login""#),
        event(1020, "Notification", "a", extra: #","msg":"Claude needs your permission to use Bash""#),
        event(1030, "PostToolUse", "a"),
        event(1070, "Stop", "a"),
        event(1080, "Notification", "a", extra: #","msg":"Claude is waiting for your input""#),
        event(1000, "SessionStart", "b"),
        event(1100, "UserPromptSubmit", "b", extra: #","prompt":"hi""#),
        event(1101, "UserPromptSubmit", "b", extra: #","prompt":"<task-notification>done""#),
        event(1000, "SessionStart", "c"),
        event(1001, "SessionEnd", "c"),
    ].joined(separator: "\n")

    @Test func foldsEventsIntoStates() {
        let day = DayLog.parse(log, now: at(1130))
        let a = day.sessions.first { $0.id == "a" }
        let b = day.sessions.first { $0.id == "b" }
        #expect(day.prompts == 3)
        #expect(day.sessions.count == 2)
        #expect(a?.state == .idle, "the 60s input ping is not an approval")
        #expect(a?.finishedAt == at(1070))
        #expect(b?.state == .working)
        #expect(b?.task == "hi", "system turns don't replace the task")
        #expect(b?.finishedAt == nil)
        #expect(day.ended.map(\.id) == ["c"])
        #expect(day.workTime == 60 + 30, "a: 1010→1070, b: 1100→now")
    }

    @Test func permissionPromptWaits() {
        let firstThree = log.split(separator: "\n").prefix(3).joined(separator: "\n")
        #expect(DayLog.parse(firstThree, now: at(1030)).sessions.first?.state == .waiting)
    }

    @Test func dropsStaleSessions() {
        #expect(DayLog.parse(log, now: at(1130 + 4 * 3600)).sessions.isEmpty)
    }

    @Test func repeatedFailuresFlailUntilASuccess() {
        let fails = [event(1, "UserPromptSubmit", "f", extra: #","prompt":"go""#),
                     event(2, "PostToolUseFailure", "f"), event(3, "PostToolUseFailure", "f")]
        #expect(DayLog.parse(fails.joined(separator: "\n"), now: at(4)).sessions.first?.isFlailing == true)
        let recovered = (fails + [event(4, "PostToolUse", "f")]).joined(separator: "\n")
        #expect(DayLog.parse(recovered, now: at(5)).sessions.first?.isFlailing == false)
    }

    @Test func ignoresGarbageLines() {
        let day = DayLog.parse("not json\n{}\n" + event(5, "SessionStart", "z"), now: at(6))
        #expect(day.sessions.map(\.id) == ["z"])
    }

    @Test func sortsApprovalFirst() {
        let s = { (id: String, state: WorkState, unread: Bool, t: TimeInterval) in
            Session(id: id, project: id, state: state, since: at(t), lastEvent: at(t), unread: unread)
        }
        let sorted = [s("idle", .idle, false, 9), s("work", .working, false, 8),
                      s("unread", .idle, true, 1), s("wait", .waiting, false, 0)].sorted(by: Session.byUrgency)
        #expect(sorted.map(\.id) == ["wait", "unread", "work", "idle"])
    }
}

@Suite("Cast")
struct CastTests {
    func session(_ state: WorkState, since: TimeInterval = 0, unread: Bool = false, fails: Int = 0) -> Session {
        Session(id: UUID().uuidString, project: "p", state: state, since: at(since), lastEvent: at(since),
                failStreak: fails, unread: unread)
    }

    func noon() -> Date { Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)! }

    @Test func napsWhenNothingIsActive() {
        let cast = Cast.make(sessions: [session(.idle)], tick: 3, now: noon(), clockOuts: [])
        #expect(cast.poses == [.sleep])
        #expect(!cast.isAnimated)
    }

    @Test func mapsStatesToPoses() {
        let now = noon()
        let cast = Cast.make(sessions: [session(.working, since: now.timeIntervalSince1970),
                                        session(.waiting, since: now.timeIntervalSince1970),
                                        session(.idle, unread: true),
                                        session(.working, fails: 2)],
                             tick: 0, now: now, clockOuts: [])
        #expect(cast.poses == [.swim(0, night: false), .roll(1, urgent: false), .chew(0), .flail(1)])
    }

    @Test func neglectedApprovalFlashes() {
        let now = noon()
        let waiting = session(.waiting, since: now.timeIntervalSince1970 - Session.neglectAfter - 1)
        let cast = Cast.make(sessions: [waiting], tick: 1, now: now, clockOuts: [])
        #expect(cast.poses == [.roll(1, urgent: true)])
        #expect(cast.poses[0].flashesRed)
    }

    @Test func overtimeStartsAtSeven() {
        let cal = Calendar.current
        let at = { (h: Int, m: Int) in cal.date(bySettingHour: h, minute: m, second: 0, of: .now)! }
        #expect(!Cast.isOvertime(at(18, 59)))
        #expect(Cast.isOvertime(at(19, 0)))
        #expect(Cast.isOvertime(at(4, 59)))
        #expect(!Cast.isOvertime(at(5, 0)))
    }

    @Test func capsAtFiveAndCountsTheRest() {
        let cast = Cast.make(sessions: (0..<7).map { _ in session(.working) }, tick: 0, now: noon(), clockOuts: [])
        #expect(cast.poses.count == Cast.maxShown)
        #expect(cast.overflow == 2)
    }

    @Test func framesWrapSoTheCacheStaysBounded() {
        let sessions = [session(.working), session(.waiting, since: 0), session(.idle, unread: true)]
        let distinct = Set((0..<10_000).map { Cast.make(sessions: sessions, tick: $0, now: noon(), clockOuts: []) })
        #expect(distinct.count <= 12)
    }

    @Test func clockOutFlingPlaysThrough() {
        let now = noon()
        let cast = Cast.make(sessions: [], tick: 0, now: now, clockOuts: [now.addingTimeInterval(-0.7)])
        #expect(cast.poses == [.toss(2)])
        #expect(Pose.toss(99).rows == Sprites.toss.last, "holds the last frame")
    }

    @Test func everySpriteIs26x15() {
        let poses: [Pose] = [.sleep] + (0..<4).flatMap {
            [Pose.swim($0, night: true), .flail($0), .chew($0), .roll($0, urgent: true), .toss($0)]
        }
        for pose in poses {
            #expect(pose.rows.count == 15 && pose.rows.allSatisfy { $0.count == 26 }, "\(pose)")
        }
    }
}

@Suite("PlanUsage")
struct PlanUsageTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    func write(_ name: String, _ json: String) -> URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        try? json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func statusLineGivesResetTimes() {
        let s = write("s.json", #"{"ts":100,"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":500},"seven_day":{"used_percentage":41,"resets_at":900}}}"#)
        let usage = PlanUsage.read(statusLine: s, appHistory: dir.appending(path: "none"), now: at(200))
        #expect(usage.fiveHour == UsageWindow(percent: 23.5, resetsAt: at(500)))
        #expect(usage.weekly == UsageWindow(percent: 41, resetsAt: at(900)))
    }

    @Test func expiredWindowReadsAsZero() {
        let s = write("s.json", #"{"ts":100,"rate_limits":{"five_hour":{"used_percentage":90,"resets_at":150}}}"#)
        let usage = PlanUsage.read(statusLine: s, appHistory: dir.appending(path: "none"), now: at(200))
        #expect(usage.fiveHour == UsageWindow(percent: 0, resetsAt: nil))
    }

    @Test func newerAppSampleWinsButKeepsResetTime() {
        let s = write("s.json", #"{"ts":100,"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":500}}}"#)
        let h = write("h.json", #"{"version":2,"samples":[{"t":150000,"u":{"fh":30,"sd":7}}]}"#)
        let usage = PlanUsage.read(statusLine: s, appHistory: h, now: at(200))
        #expect(usage.fiveHour == UsageWindow(percent: 30, resetsAt: at(500)))
        #expect(usage.weekly == UsageWindow(percent: 7, resetsAt: nil))
    }

    @Test func olderAppSampleIsIgnored() {
        let s = write("s.json", #"{"ts":100,"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":500}}}"#)
        let h = write("h.json", #"{"samples":[{"t":50000,"u":{"fh":99}}]}"#)
        #expect(PlanUsage.read(statusLine: s, appHistory: h, now: at(200)).fiveHour?.percent == 10)
    }

    @Test func nothingToReadIsEmpty() {
        #expect(PlanUsage.read(statusLine: dir.appending(path: "a"), appHistory: dir.appending(path: "b"), now: at(0)).isEmpty)
    }
}

@Suite("Format & history")
struct FormatTests {
    @Test func durations() {
        #expect(Format.duration(59) == "0분")
        #expect(Format.duration(45 * 60) == "45분")
        #expect(Format.duration(125 * 60) == "2시간 5분")
        #expect(Format.duration(-30) == "0분")
        #expect(Format.ago(at(0), now: at(30)) == "방금")
        #expect(Format.ago(at(0), now: at(180)) == "3분 전")
    }

    @Test func weekStartsMonday() {
        let wednesday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 7))!
        let week = WorkHistory.week(containing: wednesday)
        #expect(week.count == 7)
        #expect(Calendar.current.component(.weekday, from: week[0]) == 2)
        #expect(Paths.dayKey(week[0]) == "2026-10-05")
    }
}

@Suite("DayLogReader", .serialized)
struct DayLogReaderTests {
    @Test func readsOnlyWhatWasAppended() throws {
        let day = Date(timeIntervalSince1970: 0)
        let file = FileManager.default.temporaryDirectory.appending(path: "capywork-reader-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        func write(_ s: String, append: Bool = true) throws {
            if append, let h = try? FileHandle(forWritingTo: file) {
                h.seekToEndOfFile(); h.write(Data(s.utf8)); try h.close()
            } else {
                try s.write(to: file, atomically: false, encoding: .utf8)
            }
        }
        let reader = DayLogReader { _ in file }
        try write(event(1, "UserPromptSubmit", "r", extra: #","prompt":"a""#) + "\n", append: false)
        #expect(reader.read(day, now: at(2)).prompts == 1)

        let half = event(3, "UserPromptSubmit", "r", extra: #","prompt":"b""#)
        try write(String(half.prefix(20)))
        #expect(reader.read(day, now: at(4)).prompts == 1, "a half-written line waits")
        try write(String(half.dropFirst(20)) + "\n" + event(5, "Stop", "r") + "\n")
        let day2 = reader.read(day, now: at(6))
        #expect(day2.prompts == 2)
        #expect(day2.sessions.first?.state == .idle)
        #expect(day2.sessions.first?.task == "b")

        try write(event(7, "SessionStart", "new") + "\n", append: false)
        #expect(reader.read(day, now: at(8)).sessions.map(\.id) == ["new"], "a shorter file starts over")
    }
}
