// Sources/ClaudeMissionControl/Services/AuthService.swift
import AppKit
import WebKit

@MainActor
final class AuthService: NSObject, ObservableObject {
    private var continuation: CheckedContinuation<(token: String, orgId: String), Error>?
    private var webView: WKWebView?
    private var window: NSWindow?

    /// Presents a WKWebView window to claude.ai, captures the session token on login.
    /// Returns the session token and orgId as a tuple.
    func authenticate() async throws -> (token: String, orgId: String) {
        guard continuation == nil else {
            throw AuthError.alreadyInProgress
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            presentLoginWindow()
        }
    }

    private func presentLoginWindow() {
        let config = WKWebViewConfiguration()
        // Clear cookies so user gets a fresh login
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 700), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to Claude"
        window.contentView = webView
        window.center()
        window.delegate = self
        self.window = window

        let url = URL(string: "https://claude.ai/login")!
        webView.load(URLRequest(url: url))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func extractSessionToken(from webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }

                guard let sessionCookie = claudeCookies.first(where: { $0.name == "sessionKeyLC" }) else {
                    return  // not logged in yet; wait for next navigation
                }
                let token = sessionCookie.value

                // Prefer the lastActiveOrg cookie (UUID string) — no extra HTTP round-trip.
                // Fall back to fetching /api/organizations if the cookie isn't present yet.
                let orgId: String
                if let orgCookie = claudeCookies.first(where: { $0.name == "lastActiveOrg" }),
                   !orgCookie.value.isEmpty {
                    orgId = orgCookie.value
                } else {
                    orgId = (try? await ClaudeAPIService().fetchOrgId(cookieHeader: "sessionKeyLC=\(token)")) ?? ""
                }

                let cont = self.continuation
                self.continuation = nil
                self.window?.close()
                cont?.resume(returning: (token: token, orgId: orgId))
            }
        }
    }
}

extension AuthService: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Check after each navigation if we have a session cookie
            // (i.e., user has successfully logged in and been redirected)
            if let url = webView.url, url.path != "/login" && url.host?.contains("claude.ai") == true {
                self.extractSessionToken(from: webView)
            }
        }
    }
}

extension AuthService: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            if continuation != nil {
                continuation?.resume(throwing: AuthError.cancelled)
                continuation = nil
            }
        }
    }
}

enum AuthError: Error {
    case cancelled
    case alreadyInProgress
    case orgNotFound
}
