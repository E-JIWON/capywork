import Foundation

public enum Format {
    /// 45분, 2시간 5분
    public static func duration(_ t: TimeInterval) -> String {
        let m = max(0, Int(t) / 60)
        return m >= 60 ? "\(m / 60)시간 \(m % 60)분" : "\(m)분"
    }

    /// 방금, 3분 전, 1시간 2분 전
    public static func ago(_ date: Date, now: Date) -> String {
        let t = now.timeIntervalSince(date)
        return t < 60 ? "방금" : "\(duration(t)) 전"
    }
}
