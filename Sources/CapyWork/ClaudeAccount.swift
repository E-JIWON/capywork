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
    enum Status: Equatable { case off, connecting, live, expired, unavailable }

    private(set) var status: Status
    private(set) var usage: PlanUsage?

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
        lastPoll = .distantPast
        Task { await poll() }
    }

    func disconnect() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        token = nil
        usage = nil
        status = .off
    }

    func poll(now: Date = .now) async {
        // An expired login only renews when `claude` runs, so check back less often.
        let every = status == .expired ? 15 * 60 : Self.pollEvery
        guard status != .off, status != .unavailable, now.timeIntervalSince(lastPoll) > every else { return }
        lastPoll = now
        if token.map({ $0.expires <= now }) ?? true {
            // Off the main thread: macOS may hold this call open while it asks for permission.
            switch await Task.detached(operation: { Self.readKeychain() }).value {
            case .success(let t): token = t
            case .failure:
                status = .unavailable  // denied or missing: stop asking until the user retries
                return
            }
        }
        guard let token, token.expires > now else { return expire() }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 10)
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let code = (response as? HTTPURLResponse)?.statusCode else { return }  // offline: keep the last numbers
        if code == 401 || code == 403 { return expire() }
        if code == 200, let fresh = PlanUsage.fromAccount(data, at: .now) {
            usage = fresh
            status = .live
        }
    }

    private func expire() {
        token = nil
        usage = nil
        status = .expired
    }

    private struct KeychainError: Error {}

    nonisolated private static func readKeychain() -> Result<(value: String, expires: Date), KeychainError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let oauth = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["claudeAiOauth"] as? [String: Any],
              let value = oauth["accessToken"] as? String, let expiresMs = oauth["expiresAt"] as? Double
        else { return .failure(KeychainError()) }
        return .success((value, Date(timeIntervalSince1970: expiresMs / 1000)))
    }
}
