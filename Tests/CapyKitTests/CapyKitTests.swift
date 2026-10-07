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

@Suite("Reset estimates")
struct ResetEstimateTests {
    let cal = Calendar.current
    func t(_ day: Int, _ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 10, day: day, hour: h, minute: m))!
    }
    func s(_ d: Date, _ fh: Double, _ sd: Double = 0) -> Sample { Sample(at: d, fiveHour: fh, weekly: sd) }

    @Test func fiveHourWindowFromFirstUseAfterZero() {
        let samples = [s(t(7, 5, 46), 60), s(t(7, 6, 1), 0), s(t(7, 6, 21), 7), s(t(7, 6, 41), 12)]
        #expect(Sample.nextFiveHourReset(samples, now: t(7, 7, 0)) == t(7, 11, 0))
    }

    @Test func fiveHourWindowFromADropWithoutZero() {
        let samples = [s(t(7, 5, 50), 60), s(t(7, 6, 5), 4), s(t(7, 6, 20), 9)]
        #expect(Sample.nextFiveHourReset(samples, now: t(7, 7, 0)) == t(7, 10, 0))
    }

    @Test func noFiveHourGuessAfterALongGapOrWhenUnused() {
        #expect(Sample.nextFiveHourReset([s(t(6, 4, 0), 0), s(t(7, 1, 30), 3)], now: t(7, 2, 0)) == nil)
        #expect(Sample.nextFiveHourReset([s(t(7, 1, 0), 9), s(t(7, 1, 20), 0)], now: t(7, 2, 0)) == nil)
    }

    @Test func weeklyResetFromOverlappingDrops() {
        // Real pattern: Wednesdays ~01:00 UTC, one week seen only through a 30h gap.
        let samples = [
            s(t(16, 0, 43), 0, 30), s(t(16, 1, 16), 0, 1),
            s(t(23, 0, 56), 0, 40), s(t(23, 1, 11), 0, 2),
            s(t(29, 19, 6), 0, 16), s(t(31, 1, 31), 0, 0),
        ]
        let now = t(31, 6, 0)
        #expect(Sample.nextWeeklyReset(samples, now: now).map { Calendar.current.dateComponents(in: TimeZone(identifier: "UTC")!, from: $0).hour } == 1)
        #expect(Sample.nextWeeklyReset(samples, now: now)! > now)
    }

    @Test func noWeeklyGuessFromOneVagueDrop() {
        #expect(Sample.nextWeeklyReset([s(t(5, 4, 0), 0, 16), s(t(7, 1, 31), 0, 0)], now: t(7, 6, 0)) == nil)
    }
}

@Suite("Stalled turns")
struct StalledTests {
    let interrupted = [event(0, "UserPromptSubmit", "s", extra: #","prompt":"go""#), event(60, "PostToolUse", "s")].joined(separator: "\n")

    @Test func silentWorkingSessionStopsCountingAfterTenMinutes() {
        let early = DayLog.parse(interrupted, now: at(300))
        #expect(early.sessions.first?.state == .working)
        let late = DayLog.parse(interrupted, now: at(60 + 11 * 60))
        #expect(late.sessions.first?.state == .idle)
        #expect(late.sessions.first?.finishedAt == nil, "an interrupted turn is not a new answer")
        #expect(late.workTime == 60, "work time stops at the last sign of life")
    }

    @Test func inputPingEndsAWorkingTurn() {
        let log = interrupted + "\n" + event(120, "Notification", "s", extra: #","msg":"Claude is waiting for your input""#)
        #expect(DayLog.parse(log, now: at(130)).sessions.first?.state == .idle)
    }
}

@Suite("Long tools and cleanup")
struct LongToolTests {
    @Test func aRunningToolKeepsTheSessionWorking() {
        let log = [event(0, "UserPromptSubmit", "s", extra: #","prompt":"build""#), event(10, "PreToolUse", "s")].joined(separator: "\n")
        #expect(DayLog.parse(log, now: at(10 + 30 * 60)).sessions.first?.state == .working, "30-minute build")
        #expect(DayLog.parse(log, now: at(10 + 61 * 60)).sessions.first?.state == .idle, "but not forever")
        let done = log + "\n" + event(20, "PostToolUse", "s")
        #expect(DayLog.parse(done, now: at(20 + 11 * 60)).sessions.first?.state == .idle, "back to the 10-minute rule")
    }

    @Test func approvalWaitSurvivesAParallelToolStart() {
        let log = [event(0, "PreToolUse", "s"), event(1, "Notification", "s", extra: #","msg":"needs your permission""#),
                   event(2, "PreToolUse", "s")].joined(separator: "\n")
        #expect(DayLog.parse(log, now: at(3)).sessions.first?.state == .waiting)
    }

    @Test func prunesOnlyOldLogs() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "capywork-prune-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let today = Calendar.current.startOfDay(for: .now)
        let names = [0, 29, 31, 400].map { Paths.dayKey(Calendar.current.date(byAdding: .day, value: -$0, to: today)!) + ".jsonl" } + ["notes.txt"]
        for n in names { FileManager.default.createFile(atPath: dir.appending(path: n).path, contents: Data()) }
        WorkHistory.pruneLogs(today: today, dir: dir)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        #expect(left == Set([names[0], names[1], "notes.txt"]))
    }
}

@Suite("Account usage")
struct AccountUsageTests {
    @Test func parsesTheUsageEndpoint() throws {
        let json = #"{"five_hour":{"utilization":22.0,"resets_at":"2026-10-07T11:00:00.364238+00:00"},"seven_day":{"utilization":49,"resets_at":"2026-10-14T01:00:01+00:00"},"seven_day_opus":null}"#
        let u = try #require(PlanUsage.fromAccount(Data(json.utf8), at: at(5)))
        #expect(u.source == .account)
        #expect(u.asOf == at(5))
        #expect(u.fiveHour?.percent == 22)
        #expect(u.fiveHour?.estimated == false)
        #expect(u.fiveHour?.resetsAt == PlanUsage.isoDate("2026-10-07T11:00:00.364+00:00"))
        #expect(u.weekly?.percent == 49)
    }

    @Test func rejectsErrors() {
        #expect(PlanUsage.fromAccount(Data(#"{"error":{"type":"authentication_error"}}"#.utf8), at: at(0)) == nil)
        #expect(PlanUsage.fromAccount(Data("nope".utf8), at: at(0)) == nil)
    }
}
