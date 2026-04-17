# Claude Mission Control — Handoff

Context file for the next Claude session. Read this start-to-finish before touching code.

## What the app is

macOS menubar (`.accessory`) SwiftUI + AppKit app that monitors Claude Pro usage (5-hour + 7-day) across multiple accounts. Polls `claude.ai/api/organizations/{uuid}/usage` with session cookies.

## Current state (as of 2026-04-17)

**Working:** Chrome cookie decryption (including the 32-byte hash-prefix fix), multi-profile enumeration, `sessionKey` extraction, full test suite (17/17 passing via `swift test`).

**Blocked:** Live API fetch fails. Two root-caused bugs; one fixed, one unfixed.

**Branch:** `claude/jovial-benz-f1624b` on worktree `.claude/worktrees/jovial-benz-f1624b/`. Main repo is elsewhere (see `git worktree list`).

## The three bugs we hit and where each stands

### Bug A — 32-byte SHA-256 hash prefix ✅ FIXED
Modern Chrome prepends SHA-256(host) to the plaintext before AES encryption. Prior decrypt returned binary garbage → caller saw nil. `ChromeCookieImporter.decrypt()` now strips 32 bytes when plaintext > 32 bytes (legacy short values untouched). Covered by test `decryptStripsHashPrefix`.

### Bug B — Wrong cookie name ✅ FIXED
`sessionKeyLC` is a Unix timestamp, not an auth token. The real auth cookie is `sessionKey` (value `sk-ant-sid02-...`). Importer now filters on `sessionKey`; `ClaudeAPIService.extractAuthCookies` reads both `sessionKey` and `lastActiveOrg` from the serialized cookie header.

### Bug C — Cloudflare JA3 / HTTP/3 over VPN ❌ BLOCKED
`URLSession` can't reach claude.ai because Cloudflare bot-mgmt rejects non-browser TLS fingerprints (JA3). Solution attempt: `WebViewFetcher` (hidden WKWebView) — passes the TLS check because it IS a browser. **But:** on the test machine the WKWebView navigation to `https://claude.ai/` fails with POSIX errno 40 (`EMSGSIZE`, "message too long") and occasionally "network connection was lost".

**Why**, per `log show --process ClaudeMissionControl`:
- QUIC/HTTP-3 UDP datagrams are being sent over VPN interface `utun4`
- `sendmsg(..., 1252 bytes) [40: Message too long]` — datagram exceeds tunnel MTU
- Cloudflare caches Alt-Svc and pushes H3; macOS doesn't fall back to H2/TCP after QUIC post-handshake failure
- User confirmed "connection is fine" for regular traffic — only QUIC breaks

**Proof:** see recent log snippet — look for `quic_conn_handle_error_inner ... Message too long` and `interface: utun4`.

### Possible fixes for Bug C (pick one, test)

1. **Ask user to disconnect VPN** for onboarding. Cheap; if CF issues cf_clearance once, it persists in keychain/cookie jar and a subsequent VPN-on poll might still work. Unknown.
2. **Force HTTP/1.1 or HTTP/2** on the WKWebView network stack. No public API for this. Possible private SPI on `WKWebViewConfiguration` or `WKWebsiteDataStore` — investigate `_WKWebsiteDataStoreConfiguration`. Risky; may not ship in production.
3. **Proxy claude.ai fetches through a local HTTP/1.1 proxy** that we spawn in-process. High complexity.
4. **Use `URLSession` with a custom TLS stack that mimics Chrome's JA3** (e.g., via utls-swift bindings). Complex, fragile.
5. **Do the fetch from inside an actual visible WKWebView** launched only on-demand (not off-screen). Sometimes the process assertions / networking paths behave differently. Low effort; try first.
6. **Clear Alt-Svc cache on each `nonPersistent()` data store** so we start on H2. Already use `.nonPersistent()`; the system Alt-Svc cache may be shared. Not easily clearable.

**Quickest path forward:** tell the user to toggle VPN off and retry — if it works, document the limitation and surface a better error message when EMSGSIZE is detected. Longer-term: option 2 via private SPI or option 5.

## Files and key line numbers

All paths relative to worktree root `/Users/alexsmith/Desktop/Claude Mission Control/.claude/worktrees/jovial-benz-f1624b/`:

- [Sources/ClaudeMissionControl/Services/ChromeCookieImporter.swift](Sources/ClaudeMissionControl/Services/ChromeCookieImporter.swift) — SQLite read + AES decrypt + multi-profile enumeration. Key method: `importClaudeSessions()` (line 47), `readSession(forProfileName:)` (line 75, used by poller for re-read), `decrypt()` (line 195).
- [Sources/ClaudeMissionControl/Services/WebViewFetcher.swift](Sources/ClaudeMissionControl/Services/WebViewFetcher.swift) — hidden WKWebView HTTP client. This is where Bug C manifests. `warmUp()` line 44 fails on loadAndWait.
- [Sources/ClaudeMissionControl/Services/ClaudeAPIService.swift](Sources/ClaudeMissionControl/Services/ClaudeAPIService.swift) — now routes all requests through `WebViewFetcher.shared`. `extractAuthCookies` (line 55) parses header for sessionKey/lastActiveOrg.
- [Sources/ClaudeMissionControl/Services/PollingService.swift](Sources/ClaudeMissionControl/Services/PollingService.swift) — `resolveCookieHeader(for:)` (line 126) re-reads Chrome cookies per poll using `chromeProfileName`.
- [Sources/ClaudeMissionControl/Views/AccountsView.swift](Sources/ClaudeMissionControl/Views/AccountsView.swift) — import flow at `importFromChrome` (line 145), per-session add at `addChromeSession` (line 183). Surfaces `error.localizedDescription` directly, which is why user sees "message too long".
- [Sources/ClaudeMissionControl/Models/Account.swift](Sources/ClaudeMissionControl/Models/Account.swift) — added `chromeProfileName: String?`.
- [Sources/ClaudeMissionControl/Stores/AccountStore.swift](Sources/ClaudeMissionControl/Stores/AccountStore.swift) — `cookieHeader(for:)` returns stored header or falls back to `sessionKeyLC=<token>` for legacy manual-paste accounts.
- [Sources/ClaudeMissionControl/Services/KeychainService.swift](Sources/ClaudeMissionControl/Services/KeychainService.swift) — separate keychain entry type for cookie headers (`com.claudemissioncontrol.cookieheaders`).
- [Sources/ClaudeMissionControl/Services/AuthService.swift](Sources/ClaudeMissionControl/Services/AuthService.swift) — **dead code**. Old WKWebView login flow. No callers. Remove when convenient.
- [Tests/ClaudeMissionControlTests/ChromeCookieImporterTests.swift](Tests/ClaudeMissionControlTests/ChromeCookieImporterTests.swift) — decrypt tests including `decryptStripsHashPrefix`.
- [Tests/ClaudeMissionControlTests/ClaudeAPIServiceTests.swift](Tests/ClaudeMissionControlTests/ClaudeAPIServiceTests.swift) — parser tests + mock mode.
- [Package.swift](Package.swift) — Swift 6.0, macOS 14, links `sqlite3`.

## How to build / run / test

```bash
cd "/Users/alexsmith/Desktop/Claude Mission Control/.claude/worktrees/jovial-benz-f1624b"
swift build                    # should be clean
swift test                     # 17/17 should pass
swift run ClaudeMissionControl # launches the menubar app
```

App lives in menubar (top-right). Click icon → "Accounts" tab → "Import from Chrome".

## How to diagnose Bug C further

```bash
# Watch live logs for WKWebView network errors:
/usr/bin/log stream --process ClaudeMissionControl --level debug \
  --predicate 'subsystem contains "apple.network" OR subsystem contains "WebKit" OR subsystem == "com.claudemissioncontrol"'
```

Look for:
- `quic_conn_handle_error_inner ... Message too long` → confirms QUIC+VPN collision
- `didFailProvisionalLoadForFrame ... code=40` → the failure surface the user sees
- `interface: utun` → the VPN tunnel causing the MTU issue

## Pending work (TodoWrite state from previous session)

All dev items complete. Only remaining: verify end-to-end against live API (blocked by Bug C).

## Architecture decisions locked in with user

- **Chrome only** for cookie import (not Safari/Arc/Firefox).
- **Second Chrome profile** is the recommended path for onboarding a second account simultaneously.
- **No new error UI state** — errors surface through existing `authError` string + `os_log`.
- **WKWebView headless fetch engine** is the chosen bypass for Cloudflare. Do not rewrite to URLSession.
- **Re-read cookies per poll** — Chrome rotates `sessionKey` silently; if we cached it we'd see auth flaps.

## Things explicitly NOT to do (user preferences)

- Don't add documentation files without being asked (this HANDOFF.md was specifically requested).
- Don't rebuild the flow as "open a visible login window" — user removed WKWebView auth (commit `a1ff86f`) because webviews don't render reliably in `.accessory` apps.
- Don't expand scope. Bug C fix first; everything else is gravy.

## Superpowers cleanup (Part A of original plan)

Already done — three deprecated stubs deleted from `/Users/alexsmith/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/commands/`: `brainstorm.md`, `write-plan.md`, `execute-plan.md`. The active skills (`brainstorming`, `writing-plans`, `executing-plans`) remain.

## Original plan doc

[`/Users/alexsmith/.claude/plans/first-in-using-superpowers-remove-validated-kurzweil.md`](/Users/alexsmith/.claude/plans/first-in-using-superpowers-remove-validated-kurzweil.md) — has the full context, reused findings, verification steps.

## Git state

Most recent commits on this branch:
- `a1ff86f` feat: replace WKWebView auth with manual token paste
- `ad50c54` chore: switch to live API mode
- `a8dbafe` feat: implement real API response parser from DevTools findings
- `7a45ec7` feat: fill in real API config from DevTools investigation
- `f30ec57` feat: wire org_id into Account model and API layer

All WKWebView-fetcher + hash-prefix + multi-profile work in this session is **uncommitted**. Run `git status` and `git diff` to see what's pending. When continuing: commit these in one logical "feat: Chrome cookie import via WKWebView" commit if tests pass; otherwise fix Bug C first.
