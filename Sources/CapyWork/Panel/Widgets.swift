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

struct AccountState {
    var status = ClaudeAccount.Status.off
    var plan: String?
    var checkedAt: Date?
}

struct AccountActions {
    var connect: () -> Void = {}
    var check: () -> Void = {}
    var openTerminal: () -> Void = {}
    var disconnect: () -> Void = {}
}

struct UsageSection: View {
    let usage: PlanUsage
    let account: AccountState
    let actions: AccountActions

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("사용량").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if account.status == .live {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("실시간").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.green)
                    }
                } else if let asOf = usage.asOf {
                    Text("추정 · \(asOf.formatted(date: .omitted, time: .shortened)) 기준")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
            if let w = usage.fiveHour { UsageBar(title: "5시간", window: w) }
            if let w = usage.weekly { UsageBar(title: "주간", window: w) }
            AccountCard(account: account, actions: actions)
        }
    }
}

/// Says where the account connection stands and exactly what to do next.
struct AccountCard: View {
    let account: AccountState
    let actions: AccountActions

    var body: some View {
        switch account.status {
        case .off:
            ConnectButton(action: actions.connect)
        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude Code 로그인 확인 중…").font(.system(size: 11.5, weight: .semibold))
                    Text("키체인 창이 뜨면 「항상 허용」을 눌러 주세요").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
        case .live:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 11))
                Text("Claude 계정 연결됨").font(.system(size: 11, weight: .semibold))
                if let plan = account.plan { Text(plan.capitalized).font(.system(size: 10.5)).foregroundStyle(.secondary) }
                if let at = account.checkedAt {
                    Text("· \(at.formatted(date: .omitted, time: .shortened)) 업데이트").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
                Spacer()
                Button("연결 끊기", action: actions.disconnect).buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            .padding(.top, 2)
        case .expired:
            Notice(
                title: "로그인을 새로 고치면 정확해져요",
                message: "지금은 추정값이에요. 카피 출근부는 Claude Code(터미널)의 로그인을 빌려 쓰는데, 그 로그인이 만료됐어요.",
                steps: ["터미널 열기 → ⌘V → Enter 로 claude 실행", "아무 메시지나 한 번 보내기", "지금 확인 누르기"],
                primary: ("터미널 열기", actions.openTerminal), secondary: ("지금 확인", actions.check),
                disconnect: actions.disconnect)
        case .missing:
            Notice(
                title: "Claude Code 로그인이 없어요",
                message: "카피 출근부는 Claude Code(터미널)의 로그인을 빌려 써요. 터미널에서 claude 를 실행해 로그인해 주세요.",
                steps: ["터미널 열기 → ⌘V → Enter 로 claude 실행", "안내에 따라 로그인", "다시 확인 누르기"],
                primary: ("터미널 열기", actions.openTerminal), secondary: ("다시 확인", actions.check),
                disconnect: actions.disconnect)
        case .denied:
            Notice(
                title: "키체인 접근이 거절됐어요",
                message: "다시 확인을 누르고, macOS 창이 뜨면 「항상 허용」을 눌러 주세요.",
                steps: [],
                primary: ("다시 확인", actions.check), secondary: nil,
                disconnect: actions.disconnect)
        }
    }
}

struct Notice: View {
    let title: String
    let message: String
    let steps: [String]
    let primary: (String, () -> Void)
    let secondary: (String, () -> Void)?
    let disconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.claudeOrange)
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            Text(message).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(i + 1)").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 15, height: 15).background(Theme.claudeOrange.opacity(0.85), in: Circle())
                            Text(step).font(.system(size: 10.5))
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Button(primary.0, action: primary.1).buttonStyle(PillButton(prominent: true))
                if let secondary { Button(secondary.0, action: secondary.1).buttonStyle(PillButton(prominent: false)) }
                Spacer()
                Button("연결 끊기", action: disconnect).buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Theme.claudeOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.claudeOrange.opacity(0.25)))
        .padding(.top, 2)
    }
}

struct PillButton: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(prominent ? AnyShapeStyle(Theme.claudeOrange) : AnyShapeStyle(.primary.opacity(0.08)), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The optional "sign in for exact numbers" offer: a real button, but clearly skippable.
struct ConnectButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.claudeOrange)
                    .frame(width: 26, height: 26)
                    .background(Theme.claudeOrange.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude 계정으로 정확하게 보기").font(.system(size: 12, weight: .semibold))
                    Text("선택 사항 · 안 해도 추정값으로 보여요").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text("연결").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.claudeOrange, in: Capsule())
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 9).fill(.primary.opacity(hovering ? 0.09 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.top, 2)
        .help("Claude Code 로그인 정보(키체인)로 정확한 사용량과 초기화 시각을 가져와요")
        .accessibilityHint("키체인 접근을 물어봐요")
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
        return "\(about)\(resets.formatted(.dateTime.weekday(.abbreviated))) \(resets.formatted(date: .omitted, time: .shortened)) 초기화"
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
