import Foundation

public enum WorkState: Int, Comparable, Sendable {
    case idle, working, waiting

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct Session: Identifiable, Sendable {
    public let id: String
    public let project: String
    public var state: WorkState
    public var task: String
    /// When `state` last changed.
    public var since: Date
    public var lastEvent: Date
    /// Title and id from the Claude desktop app, when it knows this session.
    public var title: String
    public var desktopID: String?
    public var finishedAt: Date?
    public var failStreak: Int
    public var unread: Bool
    /// Hidden from the panel list and the menu bar via right-click, in CapyWork only.
    public var hidden = false

    public init(id: String, project: String, state: WorkState = .idle, task: String = "",
                since: Date, lastEvent: Date, title: String = "", desktopID: String? = nil,
                finishedAt: Date? = nil, failStreak: Int = 0, unread: Bool = false) {
        self.id = id
        self.project = project
        self.state = state
        self.task = task
        self.since = since
        self.lastEvent = lastEvent
        self.title = title
        self.desktopID = desktopID
        self.finishedAt = finishedAt
        self.failStreak = failStreak
        self.unread = unread
    }

    public var name: String { title.isEmpty ? project : title }
    public var isFlailing: Bool { state == .working && failStreak >= 2 }
    public var hasUnread: Bool { state == .idle && unread }
    public var needsYou: Bool { state == .waiting || hasUnread }
    /// Shown in the menu bar: busy, or waiting on you.
    public var isActive: Bool { !hidden && (state != .idle || hasUnread) }

    public static let neglectAfter: TimeInterval = 5 * 60
    public func isNeglected(now: Date) -> Bool {
        state == .waiting && now.timeIntervalSince(since) > Self.neglectAfter
    }

    /// Approval > unread > working > idle, then most recent first.
    public static func byUrgency(_ a: Session, _ b: Session) -> Bool {
        (a.rank, a.lastEvent) > (b.rank, b.lastEvent)
    }

    var rank: Int { hidden ? -1 : state == .waiting ? 3 : hasUnread ? 2 : state == .working ? 1 : 0 }
}
