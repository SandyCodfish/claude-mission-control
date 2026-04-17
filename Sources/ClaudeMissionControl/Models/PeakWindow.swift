// Sources/ClaudeMissionControl/Models/PeakWindow.swift
import Foundation

struct PeakWindow: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var startHour: Int      // 0–23
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var timeZoneIdentifier: String  // e.g. "Asia/Shanghai"
    var isEnabled: Bool

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    init(
        id: UUID = UUID(),
        name: String,
        startHour: Int, startMinute: Int = 0,
        endHour: Int, endMinute: Int = 0,
        timeZoneIdentifier: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isEnabled = isEnabled
    }

    func isActive(at date: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        var cal = Calendar.current
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.hour, .minute], from: date)
        guard let hour = comps.hour, let minute = comps.minute else { return false }
        let nowMins = hour * 60 + minute
        let startMins = startHour * 60 + startMinute
        let endMins = endHour * 60 + endMinute
        // Special case: if start equals end, window is always active (24-hour span)
        if startMins == endMins {
            return true  // start == end means 24-hour window (always active)
        }
        if startMins <= endMins {
            return nowMins >= startMins && nowMins < endMins
        } else {
            // crosses midnight
            return nowMins >= startMins || nowMins < endMins
        }
    }

    static let defaults: [PeakWindow] = [
        PeakWindow(name: "China Peak", startHour: 21, endHour: 3,
                   timeZoneIdentifier: "Asia/Shanghai", isEnabled: true),
        PeakWindow(name: "US Business Hours", startHour: 9, endHour: 17,
                   timeZoneIdentifier: "America/New_York", isEnabled: false)
    ]
}
