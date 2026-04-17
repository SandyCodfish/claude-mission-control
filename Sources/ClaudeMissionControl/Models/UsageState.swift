// Sources/ClaudeMissionControl/Models/UsageState.swift
import Foundation

struct UsageState: Sendable {
    var fiveHourUsage: Double       // 0.0–1.0
    var fiveHourResetTime: Date?    // nil if not limited
    var weeklyUsage: Double         // 0.0–1.0
    var weeklyResetTime: Date?
    var lastUpdated: Date

    var isLimited: Bool {
        fiveHourUsage >= 1.0 || weeklyUsage >= 1.0
    }

    var isFiveHourLimited: Bool { fiveHourUsage >= 1.0 }
    var isWeeklyLimited: Bool  { weeklyUsage >= 1.0 }

    static let empty = UsageState(
        fiveHourUsage: 0,
        fiveHourResetTime: nil,
        weeklyUsage: 0,
        weeklyResetTime: nil,
        lastUpdated: .distantPast
    )

    static func mock() -> UsageState {
        UsageState(
            fiveHourUsage: 0.35,
            fiveHourResetTime: Date().addingTimeInterval(2 * 3600 + 15 * 60),
            weeklyUsage: 0.58,
            weeklyResetTime: Calendar.current.nextDate(
                after: Date(),
                matching: DateComponents(weekday: 5),
                matchingPolicy: .nextTime
            ),
            lastUpdated: Date()
        )
    }
}
