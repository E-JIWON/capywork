import Foundation

public enum Pose: Hashable, Sendable {
    case sleep
    case swim(Int, night: Bool)
    case flail(Int)
    case chew(Int)
    case roll(Int, urgent: Bool)
    case toss(Int)

    public var rows: [String] {
        switch self {
        case .swim(let f, _): Sprites.swim[f % Sprites.swim.count]
        case .flail(let f): Sprites.flail[f % Sprites.flail.count]
        case .chew(let f): Sprites.chew[f % Sprites.chew.count]
        case .roll(let f, _): Sprites.roll[f % Sprites.roll.count]
        case .toss(let f): Sprites.toss[min(f, Sprites.toss.count - 1)]
        case .sleep: Sprites.sleep
        }
    }

    public var flashesRed: Bool {
        if case .roll(let f, true) = self { return f % 2 == 1 }
        return false
    }

    public var showsMoon: Bool {
        if case .swim(_, true) = self { return true }
        return false
    }
}

/// Which capybaras the menu bar shows: one per active session, a clock-out fling for each
/// session that just ended, or a single napping one when nothing's going on.
public struct Cast: Hashable, Sendable {
    public var poses: [Pose]
    public var overflow: Int

    public init(poses: [Pose], overflow: Int) {
        self.poses = poses
        self.overflow = overflow
    }

    public static let napping = Cast(poses: [.sleep], overflow: 0)
    public static let maxShown = 5
    public static let tossFrameTime: TimeInterval = 0.3
    public static let tossDuration = tossFrameTime * Double(Sprites.toss.count)

    /// `tick` advances every 0.15s; most poses step every other tick, neglected approvals every tick.
    public static func make(sessions: [Session], tick: Int, now: Date, clockOuts: [Date]) -> Cast {
        let active = sessions.filter(\.isActive)
        let night = isOvertime(now)
        let step = tick / 2
        // Frames wrap so equal pictures compare equal and the icon cache stays small.
        var poses: [Pose] = active.prefix(maxShown).enumerated().map { i, s in
            switch s.state {
            case .working:
                s.isFlailing ? .flail((step + i) % Sprites.flail.count)
                             : .swim((step + i) % Sprites.swim.count, night: night)
            case .waiting:
                s.isNeglected(now: now) ? .roll((tick + i) % (Sprites.roll.count * 2), urgent: true)
                                        : .roll((step + i) % Sprites.roll.count, urgent: false)
            case .idle: .chew((step + i) % Sprites.chew.count)
            }
        }
        poses += clockOuts.map { .toss(min(Int(now.timeIntervalSince($0) / tossFrameTime), Sprites.toss.count - 1)) }
        return poses.isEmpty ? napping : Cast(poses: poses, overflow: max(0, active.count - maxShown))
    }

    public var isAnimated: Bool { self != Self.napping }

    /// 야근: 7pm to 5am.
    public static func isOvertime(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 19 || hour < 5
    }
}
