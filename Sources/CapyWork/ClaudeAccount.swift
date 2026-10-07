import AppKit
import CapyKit
import Foundation
import Observation
import Security

/// Optional: exact plan usage from the account Claude Code is signed in with.
/// Reads Claude Code's keychain entry (macOS asks once) and never refreshes or stores the token,
/// so it can't disturb Claude Code's own login. When that login has expired, the panel falls back
/// to the local estimate until `claude` runs again and renews it.
@MainActor @Observable
final class ClaudeAccount {
    enum Status: Equatable {
        case off, connecting, live, expired
        /// No Claude Code login in the keychain at all.
        case missing
        /// The user said no to the keychain prompt.
        case denied
    }

    private(set) var status: Status
    private(set) var usage: PlanUsage?
    private(set) var plan: String?
    private(set) var checkedAt: Date?

    @ObservationIgnored private var token: (value: String, expires: Date)?
    @ObservationIgnored private var lastPoll = Date.distantPast
    @ObservationIgnored private static let enabledKey = "accountUsage"
    static let pollEvery: TimeInterval = 180

    init() {
        status = UserDefaults.standard.bool(forKey: Self.enabledKey) ? .connecting : .off
    }

    func connect() {
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        status = .connecting
        checkNow()
    }

    func checkNow() {
        if status != .off { status = .connecting }
        lastPoll = .distantPast
        token = nil
        Task { await poll() }
    }

    func disconnect() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        token = nil
        usage = nil
        plan = nil
        status = .off
    }

    /// Opens Terminal with `claude` on the clipboard, so renewing the login is one paste away.
    func openTerminal() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("claude", forType: .string)
        NSWorkspace.shared.open(URL(filePath: "/System/Applications/Utilities/Terminal.app"))
    }

    func poll(now: Date = .now) async {
        // An expired login only renews when `claude` runs, so check back less often.
        let every = status == .expired ? 15 * 60 : Self.pollEvery
        guard [.connecting, .live, .expired].contains(status), now.timeIntervalSince(lastPoll) > every else { return }
        lastPoll = now
        if token.map({ $0.expires <= now }) ?? true {
            // Off the main thread: macOS may hold this call open while it asks for permission.
            switch await Task.detached(operation: { Self.readKeychain() }).value {
            case .found(let value, let expires, let plan):
                token = (value, expires)
                self.plan = plan
            case .missing: return settle(.missing)
            case .denied: return settle(.denied)  // stop asking until the user retries
            }
        }
        guard let token, token.expires > now else { return settle(.expired) }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 10)
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let code = (response as? HTTPURLResponse)?.statusCode else { return }  // offline: keep the last numbers
        if code == 401 || code == 403 { return settle(.expired) }
        if code == 200, let fresh = PlanUsage.fromAccount(data, at: .now) {
            usage = fresh
            checkedAt = .now
            status = .live
        }
    }

    private func settle(_ status: Status) {
        token = nil
        usage = nil
        checkedAt = .now
        self.status = status
    }

    private enum KeychainResult: Sendable { case found(String, Date, String?), missing, denied }

    nonisolated private static func readKeychain() -> KeychainResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess, let data = item as? Data,
              let oauth = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["claudeAiOauth"] as? [String: Any],
              let value = oauth["accessToken"] as? String, let expiresMs = oauth["expiresAt"] as? Double
        else { return status == errSecSuccess ? .missing : .denied }
        return .found(value, Date(timeIntervalSince1970: expiresMs / 1000), oauth["subscriptionType"] as? String)
    }
}
