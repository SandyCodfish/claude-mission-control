// Sources/ClaudeMissionControl/Services/WebViewFetcher.swift
import Foundation
import Network
import WebKit
import os.log

/// Hidden WKWebView used as an HTTP client for claude.ai.
///
/// Why this exists: claude.ai sits behind Cloudflare bot management, which rejects requests whose
/// TLS fingerprint (JA3) doesn't match a real browser — so URLSession gets 403/challenge pages
/// even with valid cookies. A WKWebView IS a real browser, so the fingerprint passes.
///
/// VPN + QUIC caveat: Cloudflare's DNS HTTPS record advertises `alpn=h3`, so WebKit tries QUIC
/// first. Over a VPN tunnel with smaller MTU the 1252-byte Initial datagram fails with
/// EMSGSIZE and WebKit doesn't fall back. WebKit exposes no public or private H3 toggle in this
/// macOS build. The workaround: route WKWebView through a local `LocalConnectProxy` on 127.0.0.1
/// that dials claude.ai with `NWParameters.tcp` (pure TCP, no QUIC). TLS stays end-to-end so
/// CF still sees a browser JA3 fingerprint.
@MainActor
final class WebViewFetcher: NSObject {
    static let shared = WebViewFetcher()

    private static let log = Logger(subsystem: "com.claudemissioncontrol", category: "webview-fetch")
    private static let warmUpURL = URL(string: "https://claude.ai/")!

    private let proxy = LocalConnectProxy()
    private var webView: WKWebView?
    private var initTask: Task<Void, Error>?
    private var warmUpTask: Task<Void, Error>?
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
    }

    /// Starts the local CONNECT proxy and builds the WKWebView pointed at it. Idempotent.
    private func ensureWebView() async throws -> WKWebView {
        if let webView { return webView }
        if let initTask {
            try await initTask.value
            return webView!
        }
        let task = Task<Void, Error> { [self] in
            try await proxy.start()

            let config = WKWebViewConfiguration()
            // Non-persistent keeps the cookie jar isolated and empty at app launch. The default
            // store inherits Safari's cookies for claude.ai, which balloons the request header.
            let dataStore = WKWebsiteDataStore.nonPersistent()

            // Route every request through our TCP-only proxy.
            let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .init(rawValue: proxy.port)!)
            dataStore.proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: endpoint)]
            config.websiteDataStore = dataStore

            let wv = WKWebView(frame: .zero, configuration: config)
            wv.navigationDelegate = self
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
            self.webView = wv
            Self.log.debug("WebViewFetcher: webview created, proxy on :\(self.proxy.port, privacy: .public)")
        }
        initTask = task
        try await task.value
        return webView!
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
            _ = try await ensureWebView()
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
    func installAuthCookies(sessionKey: String, lastActiveOrg: String?) async throws {
        let webView = try await ensureWebView()
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
        guard let webView else { throw APIError.invalidResponse }

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
        guard let webView else { throw APIError.invalidResponse }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            navigationContinuation = cont
            webView.load(URLRequest(url: url))
        }
    }

    fileprivate func finishNavigation(error: Error?) {
        let cont = navigationContinuation
        navigationContinuation = nil
        if let error { cont?.resume(throwing: error) }
        else { cont?.resume() }
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
