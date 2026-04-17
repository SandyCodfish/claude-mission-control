// Tests/ClaudeMissionControlTests/ProxiedFetchProbe.swift
//
// Opt-in (CMC_PROXY_PROBE=1). Live end-to-end test of the LocalConnectProxy + WKWebView fix for
// Bug C. Expects VPN to be on. Reads real cookies from Chrome, fetches /api/organizations/.../usage
// via WebViewFetcher (which routes through our TCP-only proxy), asserts JSON comes back.
import Testing
import Foundation
@testable import ClaudeMissionControl

@Suite("ProxiedFetchProbe", .disabled(if: ProcessInfo.processInfo.environment["CMC_PROXY_PROBE"] != "1"))
struct ProxiedFetchProbe {
    @Test("end-to-end: WKWebView via LocalConnectProxy reaches /api/.../usage over VPN")
    @MainActor
    func endToEndFetch() async throws {
        let importer = ChromeCookieImporter()
        let sessions = try importer.importClaudeSessions()
        guard let session = sessions.first else {
            Issue.record("No Chrome profile is logged into claude.ai")
            return
        }
        let orgId = session.lastActiveOrg
        guard !orgId.isEmpty else {
            Issue.record("no lastActiveOrg cookie")
            return
        }
        print("PROBE: using profile=\(session.profileName) orgId=\(orgId)")

        let api = ClaudeAPIService()
        let state = try await api.fetchUsage(
            for: UUID(), orgId: orgId, cookieHeader: session.cookieHeader
        )
        print("PROBE: ✅ usage fetched. 5h=\(state.fiveHourUsage) weekly=\(state.weeklyUsage)")
        #expect(state.lastUpdated.timeIntervalSinceNow > -5)
    }
}
