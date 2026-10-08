import AppKit
import CapyKit
import Foundation
import Observation
import Security
import WebKit

/// Optional: exact plan usage, the same numbers claude.ai shows.
/// "Claude에 로그인" opens a small claude.ai window inside CapyWork; once you're signed in it closes
/// itself, and every few minutes a hidden page in that same session asks claude.ai for usage.
/// The session lives only in CapyWork's own web data; "로그아웃" clears it.
@MainActor @Observable
final class ClaudeAccount {
    enum Status: Equatable {
        case off, checking, live
        /// claude.ai sent us back to the login page.
        case loggedOut
        /// Signed in, but the usage answer didn't look right.
        case failed
    }

    private(set) var status: Status
    private(set) var usage: PlanUsage?
    private(set) var checkedAt: Date?
    /// Why the last check failed, without any of the account's data: an HTTP code or the reply's field names.
    private(set) var problem: String?

    @ObservationIgnored private var loginWindow: NSWindow?
    @ObservationIgnored private let popups = LoginPopups()
    @ObservationIgnored private var loginWatch: Timer?
    @ObservationIgnored private var lastPoll = Date.distantPast
    @ObservationIgnored private static let enabledKey = "claudeWebLogin"
    static let pollEvery: TimeInterval = 180
    static let site = URL(string: "https://claude.ai")!

    init() {
        status = UserDefaults.standard.bool(forKey: Self.enabledKey) ? .checking : .off
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: "CapyWork Claude token"] as CFDictionary)  // retired setup-token flow
    }

    // MARK: Sign in

    func signIn() {
        if let loginWindow {
            loginWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let web = Self.webView(frame: NSRect(x: 0, y: 0, width: 520, height: 760))
        web.uiDelegate = popups  // Google / Apple sign-in open their own popup windows
        web.load(URLRequest(url: Self.site.appending(path: "login")))
        let window = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Claude 로그인 · 카피 코드 바라 (한 번만 하면 기억해요)"
        window.contentView = web
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        loginWindow = window
        loginWatch = .scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchLogin() }
        }
    }

    /// Signed in once claude.ai has set its session cookie; closing the window cancels.
    private func watchLogin() {
        guard let loginWindow, loginWindow.isVisible else { return endLogin() }
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            MainActor.assumeIsolated {
                guard cookies.contains(where: { $0.name == "sessionKey" && $0.domain.hasSuffix("claude.ai") }) else { return }
                self.endLogin()
                UserDefaults.standard.set(true, forKey: Self.enabledKey)
                self.checkNow()
            }
        }
    }

    private func endLogin() {
        loginWatch?.invalidate()
        loginWatch = nil
        loginWindow?.close()
        loginWindow = nil
        popups.closeAll()
    }

    func signOut() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        usage = nil
        checkedAt = nil
        status = .off
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                             for: records.filter { $0.displayName.contains("claude.ai") }) {}
        }
    }

    // MARK: Usage

    func checkNow() {
        status = .checking
        lastPoll = .distantPast
        Task { await poll() }
    }

    func poll(now: Date = .now) async {
        guard status == .checking || status == .live, now.timeIntervalSince(lastPoll) > Self.pollEvery else { return }
        lastPoll = now
        // A throwaway page on claude.ai, so the request goes out with the session like the site's own.
        let web = Self.webView(frame: .zero)
        web.load(URLRequest(url: Self.site.appending(path: "api/organizations")))
        for _ in 0..<100 where web.isLoading { try? await Task.sleep(for: .milliseconds(150)) }
        let reply: String
        do {
            reply = try await web.callAsyncJavaScript(Self.usageScript, contentWorld: .page) as? String ?? ""
        } catch {
            return settle(.failed, problem: "script: \((error as NSError).code)")
        }
        if reply == "signed-out" { return settle(.loggedOut) }
        guard let fresh = PlanUsage.fromAccount(Data(reply.utf8), at: .now) else {
            let keys = (try? JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any]).map { $0.keys.sorted().joined(separator: ",") }
            return settle(.failed, problem: reply.hasPrefix("http ") ? reply : "fields: \(keys ?? "not json")")
        }
        usage = fresh
        checkedAt = .now
        problem = nil
        status = .live
    }

    private func settle(_ status: Status, problem: String? = nil) {
        self.problem = problem
        usage = nil
        checkedAt = .now
        self.status = status
    }

    /// Picks the paid (or first) organization and returns its usage JSON, or "signed-out".
    static let usageScript = """
        const orgs = await fetch('/api/organizations', { credentials: 'include' });
        if (!orgs.ok) return 'signed-out';
        const list = await orgs.json();
        const paid = list.find(o => (o.capabilities || []).some(c => c.startsWith('claude_max') || c.startsWith('claude_pro')));
        const org = paid || list[0];
        if (!org) return 'signed-out';
        const usage = await fetch(`/api/organizations/${org.uuid}/usage`, { credentials: 'include' });
        return usage.ok ? await usage.text() : (usage.status === 401 || usage.status === 403 ? 'signed-out' : `http ${usage.status}`);
        """

    private static func webView(frame: NSRect) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let web = WKWebView(frame: frame, configuration: config)
        // Some sign-in providers refuse unknown embedded browsers; look like Safari.
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        return web
    }
}

/// Gives sign-in popups (Google, Apple) a real window of their own and closes it when they finish.
@MainActor
final class LoginPopups: NSObject, WKUIDelegate {
    private var windows: [NSWindow] = []

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
        popup.customUserAgent = webView.customUserAgent
        popup.uiDelegate = self
        let window = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "로그인"
        window.contentView = popup
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        windows.removeAll { window in
            guard window.contentView === webView else { return false }
            window.close()
            return true
        }
    }

    func closeAll() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }
}
