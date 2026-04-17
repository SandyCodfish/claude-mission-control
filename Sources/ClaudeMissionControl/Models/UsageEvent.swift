// Sources/ClaudeMissionControl/Models/UsageEvent.swift
import Foundation

struct UsageEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let accountName: String
    let kind: Kind

    enum Kind: String, Codable, Sendable {
        case fiveHourLimitReached   = "5-hour limit reached"
        case fiveHourLimitRestored  = "5-hour limit restored"
        case weeklyLimitReached     = "Weekly limit reached"
        case weeklyLimitRestored    = "Weekly limit restored"
    }

    var description: String { kind.rawValue }
}
