import AppKit
import Testing
@testable import CapyWork

/// Safe system calls. (VoiceOver labels can't be read headlessly: SwiftUI only builds the
/// accessibility tree while an assistive client is attached, so those are checked by hand.)
@MainActor
@Suite("Audit")
struct AuditTests {
    @Test func notificationTextSurvivesAppleScript() throws {
        let nasty = #"세션 "따옴표" \ 역슬래시 & 'quote'"#
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/osascript")
        p.arguments = ["-e", "return \(Notifier.quoted(nasty))"]
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        p.waitUntilExit()
        let echoed = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(echoed.trimmingCharacters(in: .newlines) == nasty)
    }
}
