import CapyKit
import SwiftUI

/// Container: binds the store to the presentational panel.
struct SessionPanel: View {
    let store: SessionStore

    var body: some View {
        PanelView(log: store.log, usage: store.usage, history: store.history, onOpen: store.open)
    }
}

struct PanelView: View {
    let log: DayLog
    let usage: PlanUsage
    let history: [Date: TimeInterval]
    let onOpen: (Session) -> Void

    var body: some View {
        let sessions = log.sessions
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("카피 출근부").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(Date.now.formatted(.dateTime.month().day().weekday()))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                StatTile(value: "\(sessions.filter(\.needsYou).count)", caption: "확인 필요")
                StatTile(value: "\(sessions.filter { $0.state == .working }.count)", caption: "작업 중")
                StatTile(value: Format.duration(log.workTime), caption: "오늘 근무")
            }

            if !usage.isEmpty {
                VStack(spacing: 7) {
                    if let w = usage.fiveHour { UsageBar(title: "5시간", window: w) }
                    if let w = usage.weekly { UsageBar(title: "주간", window: w) }
                }
                .padding(.vertical, 2)
            }

            if sessions.isEmpty {
                Text("지금은 아무도 일하고 있지 않아요")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { i, session in
                            if i > 0 { Divider().padding(.leading, 26).padding(.trailing, 8) }
                            SessionRow(session: session) { onOpen(session) }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 6 * 48)  // about six rows, then scroll
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, -8)
            }

            Divider()
            WeekGrass(history: history)
            Divider()

            HStack {
                if let first = log.firstEvent {
                    Text("첫 출근 \(first.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                Spacer()
                Text("우클릭하면 바로 이동").font(.system(size: 11)).foregroundStyle(.tertiary)
                Text("·").foregroundStyle(.quaternary).accessibilityHidden(true)
                Button("종료") { NSApp.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
