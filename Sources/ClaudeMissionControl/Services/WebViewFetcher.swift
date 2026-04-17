// Sources/ClaudeMissionControl/Services/WebViewFetcher.swift
import Foundation
import WebKit
import os.log

/// Hidden WKWebView used as an HTTP client for claude.ai.
///
/// Why this exists: claude.ai sits behind Cloudflare bot management, which rejects requests whose
/// TLS fingerprint (JA3) doesn't match a real browser — so URLSession gets 403/challenge pages
/// even with valid cookies. A WKWebView IS a real browser, so the fingerprint passes. We load
/// claude.ai once to earn the `cf_clearance` cookie, then inject the account's auth cookies and
/// call `fetch()` inside the page's JS context.
@MainActor
final class WebViewFetcher: NSObject {
    static let shared = WebViewFetcher()

    private static let log = Logger(subsystem: "com.claudemissioncontrol", category: "webview-fetch")
    private static let warmUpURL = URL(string: "https://claude.ai/")!

    private let webView: WKWebView
    private var warmUpTask: Task<Void, Error>?
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let config = WKWebViewConfiguration()
        // Non-persistent keeps the cookie jar isolated and empty at app launch. The default store
        // inherits Safari's cookies for claude.ai, which balloons the request header to the point
        // where the load fails with EMSGSIZE. Fresh store = clean load; we pay one CF challenge
        // per app launch in exchange.
        config.websiteDataStore = .nonPersistent()
        // Disable QUIC/HTTP-3 via private SPI. Cloudflare advertises HTTP/3 in its HTTPS DNS
        // records; when a VPN is active the resulting QUIC UDP datagrams exceed the tunnel MTU
        // (POSIX EMSGSIZE, errno 40) and macOS does not fall back to TCP. Forcing the WebKit
        // network process off QUIC makes every request use HTTP/2 over TCP, which VPN handles
        // correctly. This key is private API — acceptable for non-App-Store distribution.
        config.preferences.setValue(false, forKey: "_quicEnabled")
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        self.webView.navigationDelegate = self
        // A custom UA helps CF trust us as a desktop browser.
        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }

    /// Loads https://claude.ai/ once so the webview clears Cloudflare's bot check and stores a
    /// `cf_clearance` cookie for subsequent API fetches. Idempotent — subsequent calls wait for
    /// the same in-flight load.
    func warmUp() async throws {
        if let warmUpTask {
            try await warmUpTask.value
            return
        }
        let task = Task<Void, Error> { [self] in
            try await loadAndWait(Self.warmUpURL)
        }
        warmUpTask = task
        do {
            try await task.value
        } catch {
            // Reset so a future call can retry.
            warmUpTask = nil
            throw error
        }
    }

    /// Sets `sessionKey` and `lastActiveOrg` cookies on the webview's claude.ai cookie store.
    /// Setting by name replaces any existing cookie with the same name, so this is how we swap
    /// between accounts between fetches without wiping Cloudflare's tokens.
    func installAuthCookies(sessionKey: String, lastActiveOrg: String?) async {
        let store = webView.configuration.websiteDataStore.httpCookieStore

        let session = HTTPCookie(properties: [
            .domain: ".claude.ai",
            .path: "/",
            .name: "sessionKey",
            .value: sessionKey,
            .secure: true,
        ])
        if let session {
            await store.setCookie(session)
        }

        if let orgId = lastActiveOrg, !orgId.isEmpty,
           let cookie = HTTPCookie(properties: [
               .domain: ".claude.ai",
               .path: "/",
               .name: "lastActiveOrg",
               .value: orgId,
               .secure: true,
           ]) {
            await store.setCookie(cookie)
        }
    }

    /// Executes `fetch(url)` inside the webview's JS context. Returns the raw response body.
    /// Throws `APIError.unauthorized` on 401/403, `APIError.httpError` for other non-200 statuses.
    func fetchJSON(url: String) async throws -> Data {
        try await warmUp()

        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript(
                """
                const r = await fetch(url, {
                    credentials: 'include',
                    headers: { 'Accept': 'application/json' }
                });
                const body = await r.text();
                return { status: r.status, body: body };
                """,
                arguments: ["url": url],
                contentWorld: .page
            )
        } catch {
            Self.log.error("callAsyncJavaScript failed: \(error.localizedDescription, privacy: .public)")
            throw APIError.invalidResponse
        }

        guard let dict = result as? [String: Any],
              let status = dict["status"] as? Int,
              let body = dict["body"] as? String else {
            Self.log.error("fetchJSON: unexpected JS return shape: \(String(describing: result), privacy: .public)")
            throw APIError.invalidResponse
        }

        switch status {
        case 200:
            return Data(body.utf8)
        case 401, 403:
            throw APIError.unauthorized
        default:
            Self.log.error("fetchJSON: HTTP \(status) for \(url, privacy: .public)")
            throw APIError.httpError(status)
        }
    }

    // MARK: - Navigation plumbing

    private func loadAndWait(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            navigationContinuation = cont
            webView.load(URLRequest(url: url))
        }
    }

    fileprivate func finishNavigation(error: Error?) {
        let cont = navigationContinuation
        navigationContinuation = nil
        guard let error else { cont?.resume(); return }

        // POSIX EMSGSIZE (errno 40): QUIC/HTTP-3 UDP datagrams exceed VPN tunnel MTU.
        // macOS does not fall back to H2/TCP after a QUIC post-handshake failure, so the
        // navigation dies with "message too long". Surface this as a specific error so the
        // UI can tell the user to disconnect their VPN rather than showing a raw OS error.
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && ns.code == 40 {
            Self.log.error("warmUp failed: EMSGSIZE — VPN MTU too small for QUIC datagrams")
            warmUpTask = nil  // allow retry after user toggles VPN
            cont?.resume(throwing: APIError.vpnBlocked)
        } else {
            cont?.resume(throwing: error)
        }
    }
}

extension WebViewFetcher: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finishNavigation(error: nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finishNavigation(error: error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finishNavigation(error: error) }
    }
}
