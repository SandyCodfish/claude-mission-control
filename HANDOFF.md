# Claude Mission Control — Handoff

Context file for the next Claude session. Read this start-to-finish before touching code.

## What the app is

macOS menubar (`.accessory`) SwiftUI + AppKit app that monitors Claude Pro usage (5-hour + 7-day) across multiple accounts. Polls `claude.ai/api/organizations/{uuid}/usage` with session cookies.

## Current state (as of 2026-04-17 19:00 GMT+8)

**Working:** Chrome cookie import + decrypt + multi-profile, usage polling via WKWebView, full test suite (17/17 passing via `swift test`).

**All 3 bugs FIXED.**

**Repo:** `https://github.com/SandyCodfish/claude-mission-control` (branch `main`)

## The three bugs and their fixes

### Bug A — 32-byte SHA-256 hash prefix ✅ FIXED
Modern Chrome prepends SHA-256(host) to the plaintext before AES encryption. `ChromeCookieImporter.decrypt()` strips 32 bytes when plaintext > 32 bytes.

### Bug B — Wrong cookie name ✅ FIXED
`sessionKeyLC` is a Unix timestamp, not an auth token. The real auth cookie is `sessionKey` (value `sk-ant-sid02-...`). Importer filters on `sessionKey`; `ClaudeAPIService` reads both `sessionKey` and `lastActiveOrg`.

### Bug C — VPN + QUIC/H3 MTU Block ✅ FIXED
Cloudflare advertises `alpn=h3` via DNS HTTPS records, so WKWebView tries QUIC first. Over VPN tunnels with small MTU, the 1252-byte QUIC Initial packet fails with `EMSGSIZE`. macOS doesn't fall back to HTTP/2.

**Solution — `LocalConnectProxy.swift`:**
- Local TCP CONNECT proxy on `127.0.0.1` (dynamically assigned port)
- WKWebView routes ALL requests through this proxy via `WKWebsiteDataStore.proxyConfigurations`
- Proxy parses `CONNECT host:port HTTP/1.1`, dials target using `NWParameters.tcp` (pure TCP, no QUIC), pumps bytes bidirectionally
- TLS stays end-to-end → Cloudflare still sees real browser JA3 fingerprint ✅

**Windows adaptation required:** `LocalConnectProxy` uses `Network.framework` which is **macOS-only**. On Windows you'll need a cross-platform TCP proxy (e.g., SwiftNIO-based or simple socket-based). The rest of the WebViewFetcher architecture is platform-agnostic.

## Files and key line numbers

All paths relative to repo root `Sources/ClaudeMissionControl/`:

- `Services/ChromeCookieImporter.swift` — SQLite read + AES decrypt + multi-profile enumeration. Key method: `importClaudeSessions()`, `readSession(forProfileName:)`, `decrypt()` (handles 32-byte hash prefix strip).
- `Services/LocalConnectProxy.swift` — **macOS-only** TCP CONNECT proxy. 194 lines. Replace with Windows-equivalent for Windows builds.
- `Services/WebViewFetcher.swift` — Hidden WKWebView HTTP client. Routes through `LocalConnectProxy`. Lazy init. `warmUp()` clears Cloudflare challenge. `installAuthCookies()` injects per-account session. `fetchJSON()` calls `fetch()` in page JS context.
- `Services/ClaudeAPIService.swift` — Routes all requests through `WebViewFetcher`. `extractAuthCookies()` parses cookie header for sessionKey/lastActiveOrg.
- `Services/PollingService.swift` — `resolveCookieHeader(for:)` re-reads Chrome cookies per poll.
- `Services/KeychainService.swift` — Stores tokens per account UUID in macOS Keychain.
- `Views/AccountsView.swift` — "Import from Chrome" primary CTA, "Refresh from Chrome" per-account, manual paste fallback.
- `Stores/AccountStore.swift` — Stores accounts + org IDs in UserDefaults.
- `Models/Account.swift` — Fields: `id`, `name`, `email`, `orgId`, `isConnected`, `chromeProfileName`.
- `App/AppDelegate.swift` — App entry, sets up menu bar.
- `App/MenuBarController.swift` — Menu bar icon + popover.
- `Package.swift` — Swift 6.0, macOS 14, links `sqlite3`.

Tests in `Tests/ClaudeMissionControlTests/`: ChromeCookieImporterTests, ClaudeAPIServiceTests, KeychainServiceTests, PeakHourServiceTests, UsageStoreTests.

## How to build / run / test

```bash
git clone https://github.com/SandyCodfish/claude-mission-control.git
cd claude-mission-control
swift build                    # should be clean
swift test                     # 17/17 should pass
swift run ClaudeMissionControl # launches the menubar app
```

For Windows: replace `LocalConnectProxy.swift` with a cross-platform TCP proxy implementation before building.

## How to diagnose network issues

```bash
# macOS — watch live logs:
log stream --process ClaudeMissionControl --level debug \
  --predicate 'subsystem contains "com.claudemissioncontrol"'
```

Look for `LocalConnectProxy listening on 127.0.0.1:` to confirm proxy started, and `proxy: CONNECT claude.ai` for successful tunnels.

## Architecture decisions

- **Chrome only** for cookie import (not Safari/Arc/Firefox).
- **Second Chrome profile** is recommended for second account simultaneously.
- **Re-read cookies per poll** — Chrome rotates `sessionKey` silently.
- **WKWebView headless fetch** is the Cloudflare bypass. Don't replace with URLSession.
- **Full cookie jar** sent with every request (not just sessionKey).

## Things NOT to do

- Don't rebuild as "open a visible login window" — `.accessory` apps don't render webviews reliably.
- Don't expand scope beyond core polling + import.
- Don't commit without running `swift test` first.
