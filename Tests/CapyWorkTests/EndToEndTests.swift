import CapyKit
import Foundation
import Testing
@testable import CapyWork

/// Drives the real scripts/hook.sh and scripts/statusline.sh into a sandbox, then checks what the
/// store shows: menu bar poses, notifications, usage. Same path as a live Claude Code session.
@MainActor
@Suite("End to end", .serialized)
struct EndToEndTests {
    static let home: URL = {
        let dir = FileManager.default.temporaryDirectory.appending(path: "capywork-e2e-\(UUID().uuidString)")
        setenv("CAPYWORK_HOME", dir.appending(path: ".capywork").path, 1)
        return dir
    }()
    static let scripts = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../scripts").standardized

    func run(_ script: String, _ json: String) throws {
        let p = Process()
        p.executableURL = URL(filePath: "/bin/sh")
        p.arguments = [Self.scripts.appending(path: script).path]
        p.environment = ["HOME": Self.home.path, "PATH": "/usr/bin:/bin"]
        let stdin = Pipe()
        p.standardInput = stdin
        try p.run()
        stdin.fileHandleForWriting.write(Data(json.utf8))
        try stdin.fileHandleForWriting.close()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
    }

    func hook(_ event: String, _ extra: String = "") throws {
        try run("hook.sh", #"{"hook_event_name":"\#(event)","session_id":"qa","cwd":"/tmp/qa-project"\#(extra)}"#)
    }

    @Test func sessionLifecycle() throws {
        _ = Self.home
        let store = SessionStore()
        var notes: [String] = []
        store.notify = { title, _ in notes.append(title) }
        let start = Date.now

        try hook("SessionStart")
        try hook("UserPromptSubmit", #","prompt":"로그인 고쳐줘""#)
        store.refresh(now: start)
        #expect(store.cast.poses.count == 1)
        guard case .swim = store.cast.poses[0] else { Issue.record("working → swim, got \(store.cast)"); return }
        #expect(store.summary == "카피 출근부: 작업 중 1")
        #expect(store.log.sessions.first?.task == "로그인 고쳐줘")
        #expect(store.log.sessions.first?.project == "qa-project")

        try hook("Notification", #","message":"Claude needs your permission to use Bash""#)
        store.refresh(now: start + 1)
        #expect(store.cast.poses.first.map { if case .roll(_, false) = $0 { true } else { false } } == true)
        #expect(notes == ["결재 대기 · qa-project"])
        store.refresh(now: start + 2)
        #expect(notes.count == 1, "notifies once per wait")

        store.refresh(now: start + Session.neglectAfter + 5)
        #expect(store.cast.poses.first.map { if case .roll(_, true) = $0 { true } else { false } } == true)
        #expect(notes.last == "결재 5분째 대기 · qa-project")

        try hook("PostToolUse")
        try hook("PostToolUseFailure")
        try hook("PostToolUseFailure")
        store.refresh(now: .now)
        #expect(store.cast.poses.first.map { if case .flail = $0 { true } else { false } } == true)
        #expect(store.log.sessions.first?.statusText == "에러 반복")

        try hook("Stop")
        store.refresh(now: .now)
        #expect(store.log.sessions.first?.state == .idle)
        #expect(store.cast == .napping, "terminal-only sessions can't be unread, so nobody is active")

        try hook("SessionEnd")
        store.refresh(now: .now)
        #expect(store.log.sessions.isEmpty)
        #expect(store.cast.poses.first.map { if case .toss = $0 { true } else { false } } == true, "clock-out fling")
        store.refresh(now: .now + Cast.tossDuration + 1)
        #expect(store.cast == .napping)
    }

    @Test func statusLineFeedsUsage() throws {
        _ = Self.home
        let resets = Int(Date.now.timeIntervalSince1970) + 3600
        try run("statusline.sh", #"{"model":{},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":\#(resets)}}}"#)
        let store = SessionStore()
        store.notify = { _, _ in }
        store.refresh()
        // The percent may come from the Claude app's newer sample; the reset time only exists here.
        #expect(store.usage.fiveHour?.resetsAt == Date(timeIntervalSince1970: TimeInterval(resets)))

        try run("statusline.sh", #"{"model":{}}"#)
        #expect(FileManager.default.fileExists(atPath: Paths.statusLineSnapshot.path), "a payload without limits keeps the last snapshot")
    }
}
