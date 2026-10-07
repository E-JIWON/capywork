import CapyKit
import SwiftUI

struct SessionRow: View {
    let session: Session
    let onOpen: () -> Void

    @State private var hovering = false
    @State private var pulsing = false

    private var openable: Bool { session.desktopID != nil }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                statusDot.alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(session.name)
                            .font(.system(size: 13, weight: session.hasUnread ? .bold : .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if hovering && openable {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        } else {
                            Text(session.statusText)
                                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(session.tint)
                            Text(elapsed)
                                .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.tertiary)
                        }
                    }
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 7).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(hovering && openable ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint(openable ? "Claude 앱에서 열기" : "")
    }

    private var elapsed: String {
        session.state == .idle ? Format.ago(session.lastEvent, now: .now)
                               : Format.duration(Date.now.timeIntervalSince(session.since))
    }

    private var subtitle: String {
        session.title.isEmpty ? session.task
                              : [session.project, session.task].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Busy sessions get a sonar ping; read idle ones a hollow ring.
    private var statusDot: some View {
        let hollow = session.state == .idle && !session.hasUnread
        return Circle()
            .strokeBorder(session.tint, lineWidth: hollow ? 1.5 : 0)
            .background(Circle().fill(hollow ? .clear : session.tint))
            .frame(width: 8, height: 8)
            .overlay {
                if session.state != .idle {
                    Circle().stroke(session.tint, lineWidth: 1.5)
                        .scaleEffect(pulsing ? 2.6 : 1).opacity(pulsing ? 0 : 0.7)
                        .animation(.easeOut(duration: session.state == .waiting ? 0.9 : 1.6)
                            .repeatForever(autoreverses: false), value: pulsing)
                        .onAppear { pulsing = true }
                }
            }
            .accessibilityHidden(true)
    }
}
