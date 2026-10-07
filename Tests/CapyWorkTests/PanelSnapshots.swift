import AppKit
import CapyKit
import SwiftUI
import Testing
@testable import CapyWork

/// Renders the panel and menu bar icon for fixed scenarios in light and dark mode
/// into .build/snapshots, for eyeballing layout changes.
@MainActor
@Suite("Snapshots")
struct PanelSnapshots {
    static let out = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../.build/snapshots").standardized

    let now = Date.now

    func session(_ id: String, _ state: WorkState, title: String = "", task: String = "", ago: TimeInterval = 120,
                 unread: Bool = false, fails: Int = 0, desktop: Bool = true) -> Session {
        Session(id: id, project: id, state: state, task: task, since: now - ago, lastEvent: now - ago / 2,
                title: title, desktopID: desktop ? "local_\(id)" : nil, finishedAt: state == .idle ? now - ago : nil,
                failStreak: fails, unread: unread)
    }

    func log(_ sessions: [Session]) -> DayLog {
        var log = DayLog()
        log.sessions = sessions.sorted(by: Session.byUrgency)
        log.firstEvent = Calendar.current.date(bySettingHour: 9, minute: 12, second: 0, of: now)
        log.prompts = 23
        log.workTime = 2 * 3600 + 41 * 60
        return log
    }

    var week: [Date: TimeInterval] {
        Dictionary(uniqueKeysWithValues: WorkHistory.week(containing: now).enumerated().map { ($1, Double($0 * 47 % 200) * 60) })
    }

    func save<V: View>(_ name: String, _ view: V) throws {
        try FileManager.default.createDirectory(at: Self.out, withIntermediateDirectories: true)
        // A real NSHostingView (not ImageRenderer), so scroll views render like they do in the popover.
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: view
                .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.97))
                .environment(\.colorScheme, scheme))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame.size = host.fittingSize
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: Self.out.appending(path: "\(name)-\(scheme).png"))
        }
    }

    @Test func busyDay() throws {
        let sessions = [
            session("a", .waiting, title: "[봉칠] 임시 이미지/텍스트 저장소 아이디어 정리하고 비교하기", task: "선반이 잘 안 나와", ago: 400),
            session("b", .idle, title: "다크패턴 방지 가이드라인 정리", task: "pdf는 링크 누르면 안 열리게", unread: true),
            session("c", .working, title: "[봉칠] 타이핑", task: "e2e 테스트에서 오류 있는지 봐줘", ago: 360),
            session("d", .working, title: "", task: "빌드가 계속 깨져", ago: 50, fails: 3, desktop: false),
            session("e", .idle, title: "진상손님 대처", task: "전부 다 했어?", ago: 3600),
            session("f", .idle, title: "[봉칠] 쾌락실 - 완료", task: "푸시까지만 해주고 마무리", ago: 7200),
        ]
        let usage = PlanUsage(fiveHour: UsageWindow(percent: 86, resetsAt: now + 2 * 3600 + 600, estimated: true),
                              weekly: UsageWindow(percent: 41, resetsAt: now + 3 * 86400))
        try save("panel-busy", PanelView(log: log(sessions), usage: usage, history: week, onOpen: { _ in }))
    }

    /// The panel used in the README / social preview.
    @Test func showcase() throws {
        func s(_ id: String, _ project: String, _ state: WorkState, _ title: String, _ task: String, ago: TimeInterval, unread: Bool = false) -> Session {
            Session(id: id, project: project, state: state, task: task, since: now - ago, lastEvent: now - ago / 3,
                    title: title, desktopID: "local_\(id)", finishedAt: state == .idle ? now - ago : nil, unread: unread)
        }
        var log = log([
            s("1", "web-shop", .waiting, "로그인 리다이렉트 버그", "테스트 돌려도 돼?", ago: 90),
            s("2", "dark-pattern-guide", .idle, "다크패턴 가이드 정리", "체크리스트 PDF로 뽑아줘", ago: 240, unread: true),
            s("3", "checkout", .working, "결제 페이지 리팩터링", "훅으로 분리하고 테스트 추가", ago: 720),
            s("4", "capywork", .working, "README 영어판", "한글이랑 똑같이 맞춰줘", ago: 180),
        ])
        log.workTime = 4 * 3600 + 12 * 60
        let usage = PlanUsage(fiveHour: UsageWindow(percent: 57, resetsAt: now + 3 * 3600 + 40 * 60, estimated: true),
                              weekly: UsageWindow(percent: 17, resetsAt: Calendar.current.nextDate(
                                after: now, matching: DateComponents(hour: 10, minute: 0, weekday: 4), matchingPolicy: .nextTime)))
        try save("showcase", PanelView(log: log, usage: usage, history: week, onOpen: { _ in }))
    }

    @Test func quietDay() throws {
        try save("panel-empty", PanelView(log: DayLog(), usage: PlanUsage(), history: [:], onOpen: { _ in }))
    }

    @Test func manySessions() throws {
        let sessions = (0..<9).map { session("s\($0)", $0 % 3 == 0 ? .working : .idle, title: "세션 \($0)", task: "작업 \($0)", unread: $0 % 2 == 0) }
        let usage = PlanUsage(fiveHour: UsageWindow(percent: 12, resetsAt: nil), weekly: nil)
        try save("panel-many", PanelView(log: log(sessions), usage: usage, history: week, onOpen: { _ in }))
    }

    @Test func menuBarIcons() throws {
        let casts: [(String, Cast)] = [
            ("napping", .napping),
            ("busy", Cast(poses: [.roll(1, urgent: true), .chew(0), .swim(0, night: true), .flail(1)], overflow: 0)),
            ("overflow", Cast(poses: Array(repeating: .swim(0, night: false), count: 5), overflow: 3)),
        ]
        for (name, cast) in casts {
            try save("icon-\(name)", Image(nsImage: MenuBarIcon.image(for: cast)).padding(6))
        }
    }
}
