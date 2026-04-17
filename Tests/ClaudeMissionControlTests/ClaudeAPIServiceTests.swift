// Tests/ClaudeMissionControlTests/ClaudeAPIServiceTests.swift
import Testing
import Foundation
@testable import ClaudeMissionControl

@Suite("ClaudeAPIService")
struct ClaudeAPIServiceTests {
    @Test("parses real API response shape correctly")
    func parsesRealAPIResponse() async throws {
        let svc = ClaudeAPIService()
        // Mirrors actual /api/organizations/{uuid}/usage response format.
        // utilization is 0–100 integer; resets_at uses microsecond ISO8601.
        let json = """
        {
            "five_hour": { "utilization": 35, "resets_at": "2026-04-19T11:00:00.497303+00:00" },
            "seven_day": { "utilization": 58, "resets_at": null },
            "seven_day_oauth_apps": null,
            "extra_usage": { "is_enabled": true, "monthly_limit": null,
                             "used_credits": 0, "utilization": null, "currency": "SGD" }
        }
        """.data(using: .utf8)!
        let state = try svc.parseUsageResponse(json)
        #expect(abs(state.fiveHourUsage - 0.35) < 0.001)
        #expect(abs(state.weeklyUsage - 0.58) < 0.001)
        #expect(state.fiveHourResetTime != nil)
        #expect(state.weeklyResetTime == nil)
    }

    @Test("treats null buckets as zero usage")
    func parsesNullBuckets() async throws {
        let svc = ClaudeAPIService()
        let json = """
        { "five_hour": null, "seven_day": null }
        """.data(using: .utf8)!
        let state = try svc.parseUsageResponse(json)
        #expect(state.fiveHourUsage == 0.0)
        #expect(state.weeklyUsage == 0.0)
        #expect(state.fiveHourResetTime == nil)
        #expect(state.weeklyResetTime == nil)
    }

    @Test("returns mock data when in mock mode")
    func mockMode() async throws {
        let svc = ClaudeAPIService(useMock: true)
        let state = try await svc.fetchUsage(for: UUID(), orgId: "", cookieHeader: "sessionKeyLC=any")
        #expect(state.fiveHourUsage > 0)
    }
}
