import AppKit
import CapyKit
import Foundation
import Observation
import Security

/// Optional: exact plan usage for the user's Claude account.
/// The user makes a long-lived token with `claude setup-token` and pastes it once; it lives in
/// CapyWork's own keychain item and is only ever sent to Anthropic's usage endpoint.
/// Without it (or if it stops working) the panel shows the local estimate.
@MainActor @Observable
final class ClaudeAccount {
    enum Status: Equatable {
        case off, checking, live
        /// Anthropic said the token is expired or revoked.
        case rejected
        /// The token works but isn't allowed to read usage.
        case forbidden
    }

    private(set) var status: Status
    private(set) var usage: PlanUsage?
    private(set) var checkedAt: Date?

    @ObservationIgnored private var lastPoll = Date.distantPast
    static let pollEvery: TimeInterval = 180

    init() {
        status = Keychain.read() == nil ? .off : .checking
    }

    /// Saves a pasted `claude setup-token` token and checks it right away.
    func connect(token: String) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, Keychain.save(token) else { return }
        status = .checking
        lastPoll = .distantPast
        Task { await poll() }
    }

    func checkNow() {
        guard status != .off else { return }
        status = .checking
        lastPoll = .distantPast
        Task { await poll() }
    }

    func disconnect() {
        Keychain.delete()
        usage = nil
        checkedAt = nil
        status = .off
    }

    /// Opens Terminal with `claude setup-token` on the clipboard: paste, Enter, sign in once.
    func openTerminal() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("claude setup-token", forType: .string)
        NSWorkspace.shared.open(URL(filePath: "/System/Applications/Utilities/Terminal.app"))
    }

    func poll(now: Date = .now) async {
        guard status == .checking || status == .live, now.timeIntervalSince(lastPoll) > Self.pollEvery else { return }
        lastPoll = now
        guard let token = Keychain.read() else { return settle(.off) }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let code = (response as? HTTPURLResponse)?.statusCode else { return }  // offline: keep the last numbers
        switch code {
        case 200:
            guard let fresh = PlanUsage.fromAccount(data, at: .now) else { return settle(.forbidden) }
            usage = fresh
            checkedAt = .now
            status = .live
        case 401: settle(.rejected)
        case 403: settle(.forbidden)
        default: break  // a server hiccup: try again next round
        }
    }

    private func settle(_ status: Status) {
        usage = nil
        checkedAt = .now
        self.status = status
    }

    /// CapyWork's own keychain item, so macOS never has to ask for another app's secrets.
    enum Keychain {
        static var base: [String: Any] { [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "CapyWork Claude token",
            kSecAttrAccount as String: "default",
        ] }

        static func read() -> String? {
            var query = base
            query[kSecReturnData as String] = true
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        static func save(_ token: String) -> Bool {
            delete()
            var item = base
            item[kSecValueData as String] = Data(token.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }

        static func delete() {
            SecItemDelete(base as CFDictionary)
        }
    }
}
