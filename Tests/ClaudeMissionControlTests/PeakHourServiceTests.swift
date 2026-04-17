// Tests/ClaudeMissionControlTests/PeakHourServiceTests.swift
import Testing
import Foundation
@testable import ClaudeMissionControl

@Suite("PeakHourService")
struct PeakHourServiceTests {
    @Test("active window detected when inside time range")
    @MainActor
    func detectsActiveWindow() {
        // Create a window that spans all 24 hours — always active
        let window = PeakWindow(name: "Always", startHour: 0, endHour: 0,
                                timeZoneIdentifier: "UTC", isEnabled: true)
        let svc = PeakHourService(windows: [window])
        #expect(svc.activeWindow() != nil)
    }

    @Test("disabled window is never active")
    @MainActor
    func disabledWindow() {
        let window = PeakWindow(name: "All Day", startHour: 0, endHour: 0,
                                timeZoneIdentifier: "UTC", isEnabled: false)
        let svc = PeakHourService(windows: [window])
        #expect(svc.activeWindow() == nil)
    }

    @Test("window spanning midnight detected correctly at 11pm")
    func midnightSpan() {
        // 21:00–03:00 UTC. Create a date at 22:00 UTC.
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 22; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        let testDate = Calendar.current.date(from: comps)!
        let window = PeakWindow(name: "Night", startHour: 21, endHour: 3,
                                timeZoneIdentifier: "UTC", isEnabled: true)
        #expect(window.isActive(at: testDate))
    }
}
