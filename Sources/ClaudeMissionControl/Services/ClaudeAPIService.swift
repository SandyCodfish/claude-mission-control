// Sources/ClaudeMissionControl/Services/ClaudeAPIService.swift
import Foundation
import os.log

final class ClaudeAPIService: Sendable {
    private let useMock: Bool
    private static let log = Logger(subsystem: "com.claudemissioncontrol", category: "api")

    init(useMock: Bool = false) {
        self.useMock = useMock
    }

    // cookieHeader: full serialized Cookie header value. The WebViewFetcher parses this and
    // extracts sessionKey + lastActiveOrg; CF cookies are already present in the webview.
    func fetchUsage(for accountId: UUID, orgId: String, cookieHeader: String) async throws -> UsageState {
        if useMock {
            try await Task.sleep(nanoseconds: 300_000_000)
            return UsageState.mock()
        }

        guard !orgId.isEmpty else {
            Self.log.error("fetchUsage: empty orgId accountId=\(accountId.uuidString.prefix(8))")
            throw APIError.invalidURL
        }
        let urlString = "https://claude.ai/api/organizations/\(orgId)/usage"

        let data = try await fetchViaWebView(urlString, cookieHeader: cookieHeader)
        let state = try parseUsageResponse(data)
        Self.log.debug("fetchUsage: accountId=\(accountId.uuidString.prefix(8)) fiveHour=\(state.fiveHourUsage, format: .fixed(precision: 2)) weekly=\(state.weeklyUsage, format: .fixed(precision: 2))")
        return state
    }

    /// Fetches the organization UUID from /api/organizations.
    /// Used as a fallback if the lastActiveOrg cookie is absent.
    func fetchOrgId(cookieHeader: String) async throws -> String {
        let data = try await fetchViaWebView("https://claude.ai/api/organizations", cookieHeader: cookieHeader)

        // Response is an array; we want the `uuid` field (string) as the org identifier.
        struct OrgItem: Decodable { let uuid: String }
        let orgs = try JSONDecoder().decode([OrgItem].self, from: data)
        guard let first = orgs.first else { throw APIError.invalidResponse }
        return first.uuid
    }

    private func fetchViaWebView(_ url: String, cookieHeader: String) async throws -> Data {
        let (sessionKey, lastActiveOrg) = Self.extractAuthCookies(from: cookieHeader)
        guard let sessionKey else {
            Self.log.error("fetchViaWebView: cookieHeader has no sessionKey")
            throw APIError.unauthorized
        }
        let fetcher = await WebViewFetcher.shared
        await fetcher.installAuthCookies(sessionKey: sessionKey, lastActiveOrg: lastActiveOrg)
        return try await fetcher.fetchJSON(url: url)
    }

    static func extractAuthCookies(from header: String) -> (sessionKey: String?, lastActiveOrg: String?) {
        var session: String?
        var org: String?
        for pair in header.split(separator: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let name = String(trimmed[..<eq])
            let value = String(trimmed[trimmed.index(after: eq)...])
            switch name {
            case "sessionKey": session = value
            case "lastActiveOrg": org = value
            default: break
            }
        }
        return (session, org)
    }

    // Internal — also used by tests
    func parseUsageResponse(_ data: Data) throws -> UsageState {
        // Each bucket can be null (API returns null for inactive/unavailable limits).
        struct Bucket: Decodable {
            let utilization: Int?   // 0–100 integer percentage
            let resets_at: String?  // ISO8601 with microseconds, null when not limited
        }
        struct Response: Decodable {
            let five_hour: Bucket?
            let seven_day: Bucket?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)

        // resets_at uses microsecond precision: "2026-04-19T11:00:00.497303+00:00"
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fiveHourUsage  = Double(decoded.five_hour?.utilization ?? 0) / 100.0
        let weeklyUsage    = Double(decoded.seven_day?.utilization ?? 0) / 100.0
        let fiveHourReset  = decoded.five_hour.flatMap { $0.resets_at }.flatMap { fmt.date(from: $0) }
        let weeklyReset    = decoded.seven_day.flatMap { $0.resets_at }.flatMap { fmt.date(from: $0) }

        return UsageState(
            fiveHourUsage: fiveHourUsage,
            fiveHourResetTime: fiveHourReset,
            weeklyUsage: weeklyUsage,
            weeklyResetTime: weeklyReset,
            lastUpdated: Date()
        )
    }
}

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case unauthorized          // triggers re-auth flow
    case httpError(Int)
    case parseError(Error)
}
