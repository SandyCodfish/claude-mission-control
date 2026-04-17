// Sources/ClaudeMissionControl/Stores/AppSettings.swift
import Foundation
import AppKit

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Polling
    @Published var pollingIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(pollingIntervalMinutes, forKey: "pollingInterval") }
    }

    // Appearance: "light", "dark", "system"
    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance") }
    }

    // Menu bar icon color-coding
    @Published var colorCodedIcon: Bool {
        didSet { UserDefaults.standard.set(colorCodedIcon, forKey: "colorCodedIcon") }
    }

    // Show in Dock
    @Published var showInDock: Bool {
        didSet {
            UserDefaults.standard.set(showInDock, forKey: "showInDock")
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        }
    }

    // Peak windows (encoded as JSON)
    @Published var peakWindows: [PeakWindow] {
        didSet {
            if let data = try? JSONEncoder().encode(peakWindows) {
                UserDefaults.standard.set(data, forKey: "peakWindows")
            }
        }
    }

    // Reminder triggers
    @Published var remindOnFiveHourReset: Bool {
        didSet { UserDefaults.standard.set(remindOnFiveHourReset, forKey: "remindOnFiveHourReset") }
    }
    @Published var remindOnWeeklyReset: Bool {
        didSet { UserDefaults.standard.set(remindOnWeeklyReset, forKey: "remindOnWeeklyReset") }
    }
    @Published var remindOnLimitReached: Bool {
        didSet { UserDefaults.standard.set(remindOnLimitReached, forKey: "remindOnLimitReached") }
    }
    @Published var remindersListName: String {
        didSet { UserDefaults.standard.set(remindersListName, forKey: "remindersListName") }
    }

    // Cached events
    func loadEvents() -> [UsageEvent] {
        guard let data = UserDefaults.standard.data(forKey: "usageEvents"),
              let events = try? JSONDecoder().decode([UsageEvent].self, from: data)
        else { return [] }
        return events
    }

    func saveEvents(_ events: [UsageEvent]) {
        let trimmed = Array(events.prefix(50))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: "usageEvents")
        }
    }

    private init() {
        let ud = UserDefaults.standard
        pollingIntervalMinutes = ud.integer(forKey: "pollingInterval").nonZero ?? 3
        appearance = ud.string(forKey: "appearance") ?? "system"
        colorCodedIcon = ud.bool(forKey: "colorCodedIcon", default: true)
        showInDock = ud.bool(forKey: "showInDock", default: false)
        remindOnFiveHourReset = ud.bool(forKey: "remindOnFiveHourReset", default: true)
        remindOnWeeklyReset = ud.bool(forKey: "remindOnWeeklyReset", default: true)
        remindOnLimitReached = ud.bool(forKey: "remindOnLimitReached", default: false)
        remindersListName = ud.string(forKey: "remindersListName") ?? "Claude Mission Control"

        if let data = ud.data(forKey: "peakWindows"),
           let windows = try? JSONDecoder().decode([PeakWindow].self, from: data) {
            peakWindows = windows
        } else {
            peakWindows = PeakWindow.defaults
        }
    }
}

// MARK: - Helpers
private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

private extension UserDefaults {
    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        return object(forKey: key) != nil ? bool(forKey: key) : defaultValue
    }
}
