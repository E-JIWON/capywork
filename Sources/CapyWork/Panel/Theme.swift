import CapyKit
import SwiftUI

enum Theme {
    static let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
}

extension Session {
    var tint: Color {
        if isFlailing { return .red }
        if hasUnread { return .blue }
        switch state {
        case .idle: return .secondary
        case .working: return Theme.claudeOrange
        case .waiting: return .red
        }
    }

    var statusText: String {
        if isFlailing { return "에러 반복" }
        if hasUnread { return "새 답변" }
        switch state {
        case .idle: return "대기"
        case .working: return "작업 중"
        case .waiting: return "결재 대기"
        }
    }
}
