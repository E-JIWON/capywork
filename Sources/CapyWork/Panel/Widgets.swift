import CapyKit
import SwiftUI

struct CountChip: View {
    let count: Int
    let label: String
    let tint: Color

    var body: some View {
        let color = count > 0 ? tint : Color.secondary
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(count > 0 ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(color.opacity(count > 0 ? 0.14 : 0.06), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct UsageBar: View {
    let title: String
    let window: UsageWindow

    private var percent: Double { min(max(window.percent, 0), 100) }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(percent >= 80 ? Color.red : Theme.claudeOrange)
                        .frame(width: max(4, geo.size.width * percent / 100))
                }
            }
            .frame(height: 6)
            Text("\(Int(percent.rounded()))%").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .frame(width: 34, alignment: .trailing)
            Text(resetText).font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.tertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 118, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) 사용량")
        .accessibilityValue("\(Int(percent.rounded()))%, \(resetText)")
    }

    private var resetText: String {
        guard let resets = window.resetsAt else { return "" }
        let about = window.estimated ? "약 " : ""
        let left = resets.timeIntervalSinceNow
        if left < 24 * 3600 { return "\(about)\(Format.duration(left)) 뒤 초기화" }
        return "\(resets.formatted(.dateTime.weekday(.abbreviated))) \(resets.formatted(date: .omitted, time: .shortened)) 초기화"
    }
}

struct WeekGrass: View {
    let history: [Date: TimeInterval]

    var body: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let days = WorkHistory.week(containing: today)
        let total = days.reduce(0) { $0 + (history[$1] ?? 0) }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("이번 주 잔디").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text("합계 \(Format.duration(total))").font(.system(size: 11)).monospacedDigit().foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let worked = history[day] ?? 0
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(day > today ? Color.primary.opacity(0.04) : shade(worked))
                            .frame(height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.primary.opacity(day == today ? 0.45 : 0), lineWidth: 1))
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10, weight: day == today ? .semibold : .regular))
                            .foregroundStyle(day == today ? .primary : .tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(day.formatted(.dateTime.month().day().weekday())) · \(Format.duration(worked))")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))) \(Format.duration(worked))")
                }
            }
        }
    }

    private func shade(_ worked: TimeInterval) -> Color {
        let minutes = worked / 60
        guard minutes >= 1 else { return .primary.opacity(0.08) }
        return Theme.claudeOrange.opacity(minutes < 30 ? 0.35 : minutes < 60 ? 0.55 : minutes < 120 ? 0.8 : 1)
    }
}
