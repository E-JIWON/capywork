import AppKit
import CapyKit
import Observation

@MainActor @Observable
final class SessionStore {
    private(set) var log = DayLog()
    private(set) var usage = PlanUsage()
    private(set) var history: [Date: TimeInterval] = [:]
    /// The menu bar capybaras. Only reassigned when the picture actually changes.
    private(set) var cast = Cast.napping
    let account = ClaudeAccount()
    @ObservationIgnored var onCastChange: ((Cast) -> Void)?
    @ObservationIgnored var notify: @MainActor (_ title: String, _ body: String, _ open: URL?) -> Void = {
        Notifier.shared.post(title: $0, body: $1, open: $2)
    }
    @ObservationIgnored var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    @ObservationIgnored var frontmostApp: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

    @ObservationIgnored private var desktop: [String: DesktopSession] = [:]
    @ObservationIgnored private var seenAt: [String: Date] = [:]
    @ObservationIgnored private var lastFinish: [String: Date] = [:]
    @ObservationIgnored private var notifiedWaiting: Set<String> = []
    @ObservationIgnored private var notifiedNeglect: Set<String> = []
    @ObservationIgnored private var celebrated: Set<String> = []
    @ObservationIgnored private var archived: Set<String> = []
    /// Session id → when it was hidden. Saved so hiding survives a relaunch.
    @ObservationIgnored private var hidden: [String: Date] = SessionStore.loadHidden()
    @ObservationIgnored private var firstRefresh = true
    @ObservationIgnored private var historyDay = Date.distantPast
    @ObservationIgnored private var backfillToday: TimeInterval = 0
    @ObservationIgnored private var lastScan = Date.distantPast
    @ObservationIgnored private let reader = DayLogReader()
    @ObservationIgnored private var desktopReadAt: [String: Date] = [:]
    @ObservationIgnored private var clockOuts: [Date] = []
    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var animation: Timer?

    init() {
        refresh()
        // ponytail: 2s polling re-parses the whole day log; switch to a file watcher if it gets slow.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    var summary: String {
        let s = log.sessions.filter { !$0.hidden }
        let parts = [("결재 대기", s.filter { $0.state == .waiting }.count),
                     ("새 답변", s.filter(\.hasUnread).count),
                     ("작업 중", s.filter { $0.state == .working }.count)]
            .filter { $0.1 > 0 }.map { "\($0.0) \($0.1)" }
        return "카피 출근부: " + (parts.isEmpty ? "쉬는 중" : parts.joined(separator: ", "))
    }

    func refresh(now: Date = .now) {
        defer { firstRefresh = false }
        let today = Calendar.current.startOfDay(for: now)
        if historyDay != today {
            historyDay = today
            history = WorkHistory.load(today: today)
            WorkHistory.pruneLogs(today: today)
            backfillToday = history[today] ?? 0
        }
        var log = reader.read(today, now: now)
        history[today] = max(log.workTime, backfillToday)
        attachDesktopInfo(to: &log, now: now)
        self.log = log
        Task { await account.poll(now: now) }
        usage = account.usage ?? PlanUsage.read(now: now)
        notifyIfNeeded(now: now)
        trackClockOuts(now: now)
        let fast = log.sessions.contains { $0.isActive && $0.isNeglected(now: now) }
        setAnimating(log.sessions.contains(where: \.isActive) || !clockOuts.isEmpty, fast: fast)
        updateCast(now: now)
    }

    private func updateCast(now: Date = .now) {
        let next = Cast.make(sessions: log.sessions, tick: tick, now: now, clockOuts: clockOuts)
        guard next != cast else { return }
        cast = next
        onCastChange?(next)
    }

    /// `tick` counts 0.15s steps. Wakes every 0.3s, or every 0.15s while a neglected approval
    /// flashes, and stops entirely while the only capybara naps.
    private func setAnimating(_ on: Bool, fast: Bool) {
        let interval: TimeInterval? = on ? (fast ? 0.15 : 0.3) : nil
        guard interval != animation?.timeInterval else { return }
        animation?.invalidate()
        animation = interval.map { interval in
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.tick += interval > 0.2 ? 2 : 1
                    self.updateCast()
                }
            }
            timer.tolerance = interval / 5
            return timer
        }
    }

    /// Opens the session in the Claude app; a terminal-only session can't be opened, so clicking marks it read.
    func open(_ session: Session) {
        seenAt[session.id] = .now
        if let url = session.desktopID.flatMap(DesktopSession.openURL(for:)) { openURL(url) }
        refresh()
    }

    /// Hides a session from CapyWork only; the Claude app and the session itself are untouched.
    func setHidden(_ session: Session, _ on: Bool) {
        if on {
            hidden[session.id] = .now
            seenAt[session.id] = .now
        } else {
            hidden[session.id] = nil
        }
        saveHidden()
        refresh()
    }

    /// Sessions are sorted by urgency, so the first one the Claude app can open is the target.
    func openMostUrgent() {
        guard let session = log.sessions.first(where: { $0.desktopID != nil && !$0.hidden }) else { return NSSound.beep() }
        open(session)
    }

    private func attachDesktopInfo(to log: inout DayLog, now: Date) {
        if log.sessions.contains(where: { desktop[$0.id] == nil }), now.timeIntervalSince(lastScan) > 30 {
            lastScan = now
            for d in DesktopSession.scan() { desktop[d.cliID] = d }
        }
        // A turn that finished while you were looking at it is already read: the focused Claude app
        // session, or (ponytail: can't tell tabs apart) any terminal session while a terminal is in front.
        let front = frontmostApp()
        let watchingDesktop = front == DesktopSession.bundleID ? desktop.values.max { $0.lastFocused < $1.lastFocused }?.cliID : nil
        let watchingTerminal = front.map(DesktopSession.terminalBundleIDs.contains) ?? false

        for i in log.sessions.indices {
            let id = log.sessions[i].id
            guard var d = desktop[id] else {
                guard let done = log.sessions[i].finishedAt else { continue }
                if done != lastFinish[id] {
                    lastFinish[id] = done
                    if watchingTerminal { seenAt[id] = done }
                }
                log.sessions[i].unread = done > seenAt[id] ?? .distantPast
                continue
            }
            // These files are ~450KB and an active session touches its own constantly.
            if now.timeIntervalSince(desktopReadAt[id] ?? .distantPast) > 10,
               DesktopSession.modificationDate(d.file) != d.modified, let fresh = DesktopSession.read(d.file) {
                d = fresh
                desktop[id] = fresh
                desktopReadAt[id] = now
            }
            log.sessions[i].title = d.title
            log.sessions[i].desktopID = d.id
            guard let done = log.sessions[i].finishedAt else { continue }
            if done != lastFinish[id] {
                lastFinish[id] = done
                if id == watchingDesktop { seenAt[id] = done }
            }
            log.sessions[i].unread = done > max(d.lastFocused, seenAt[id] ?? .distantPast)
        }
        // Archiving a Claude app session is its clock-out (the app never sends SessionEnd).
        for d in desktop.values where d.archived && !archived.contains(d.cliID) {
            archived.insert(d.cliID)
            if !firstRefresh, log.sessions.contains(where: { $0.id == d.cliID }) { log.ended.append((d.cliID, now)) }
        }
        log.sessions.removeAll { archived.contains($0.id) }
        // A hidden session comes back once it changes state into something that needs you or works.
        for i in log.sessions.indices {
            let s = log.sessions[i]
            guard let at = hidden[s.id] else { continue }
            if s.since > at && (s.state != .idle || s.hasUnread) {
                hidden[s.id] = nil
                saveHidden()
            } else {
                log.sessions[i].hidden = true
            }
        }
        log.sessions.sort(by: Session.byUrgency)
    }

    nonisolated private static func loadHidden() -> [String: Date] {
        (try? JSONDecoder().decode([String: Date].self, from: Data(contentsOf: Paths.hidden))) ?? [:]
    }

    private func saveHidden() {
        hidden = hidden.filter { Date.now.timeIntervalSince($0.value) < 7 * 86400 }
        try? JSONEncoder().encode(hidden).write(to: Paths.hidden, options: .atomic)
    }

    private func notifyIfNeeded(now: Date) {
        let waiting = log.sessions.filter { $0.state == .waiting && !$0.hidden }
        for s in waiting where !notifiedWaiting.contains(s.id) {
            notify("결재 대기 · \(s.name)", "Claude가 권한 승인을 기다리고 있어요", s.desktopID.flatMap(DesktopSession.openURL(for:)))
        }
        for s in waiting where s.isNeglected(now: now) && !notifiedNeglect.contains(s.id) {
            notify("결재 5분째 대기 · \(s.name)", "귤이 빨개지고 있어요 🍊", s.desktopID.flatMap(DesktopSession.openURL(for:)))
            notifiedNeglect.insert(s.id)
        }
        notifiedWaiting = Set(waiting.map(\.id))
        notifiedNeglect.formIntersection(notifiedWaiting)
    }

    /// Fling a yuzu only for sessions that ended just now, not ones found ended at launch.
    private func trackClockOuts(now: Date) {
        for end in log.ended where !celebrated.contains(end.id) {
            celebrated.insert(end.id)
            if now.timeIntervalSince(end.at) < 10 { clockOuts.append(now) }
        }
        clockOuts.removeAll { now.timeIntervalSince($0) > Cast.tossDuration }
    }
}
