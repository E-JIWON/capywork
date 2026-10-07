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

struct UsageSection: View {
    let usage: PlanUsage
    let account: ClaudeAccount.Status
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("사용량").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if account == .live {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("실시간").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.green)
                    }
                } else if let asOf = usage.asOf {
                    Text("추정 · \(asOf.formatted(date: .omitted, time: .shortened)) 기준")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
                if account != .off {
                    Button("연결 끊기", action: onDisconnect).buttonStyle(.plain)
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
            if let w = usage.fiveHour { UsageBar(title: "5시간", window: w) }
            if let w = usage.weekly { UsageBar(title: "주간", window: w) }
            accountFooter
        }
    }

    @ViewBuilder private var accountFooter: some View {
        switch account {
        case .off:
            Button(action: onConnect) {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").font(.system(size: 10))
                    Text("Claude 계정으로 정확하게 보기").font(.system(size: 11, weight: .medium))
                    Text("선택 · 안 해도 돼요").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .lineLimit(1)
            .help("Claude Code 로그인 정보로 정확한 사용량을 가져와요. 안 하면 추정값으로 보여요.")
            .accessibilityHint("Claude Code 로그인 정보를 읽도록 키체인 접근을 물어봐요")
        case .connecting:
            Text("연결 중… 키체인 접근을 물어보면 「항상 허용」을 눌러 주세요").font(.system(size: 10.5)).foregroundStyle(.tertiary)
        case .expired:
            Text("Claude Code 로그인이 만료됐어요. 터미널에서 claude 를 한 번 실행하면 다시 정확해져요.")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        case .unavailable:
            HStack(spacing: 6) {
                Text("Claude Code 로그인 정보를 읽지 못했어요").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Button("다시 시도", action: onConnect).buttonStyle(.plain).font(.system(size: 10.5, weight: .medium))
            }
        case .live:
            EmptyView()
        }
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
