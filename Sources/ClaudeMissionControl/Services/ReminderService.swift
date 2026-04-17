// Sources/ClaudeMissionControl/Services/ReminderService.swift
import Foundation
@preconcurrency import EventKit

@MainActor
final class ReminderService {
    private let store = EKEventStore()
    private var authorized = false
    // Track pending reminders: key = "accountName-kind.rawValue"
    private var pendingReminders: [String: String] = [:] // key → EKReminder.calendarItemIdentifier

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToReminders()
            authorized = granted
            return granted
        } catch {
            return false
        }
    }

    func createResetReminder(
        for accountName: String,
        kind: UsageEvent.Kind,
        resetTime: Date,
        listName: String
    ) async {
        guard authorized else { return }
        let key = reminderKey(accountName: accountName, kind: kind)
        // Don't create duplicate
        guard pendingReminders[key] == nil else { return }

        let calendar = reminderCalendar(named: listName)
        let reminder = EKReminder(eventStore: store)
        reminder.title = "\(accountName) — \(kind.rawValue)"
        reminder.calendar = calendar
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: resetTime
        )
        reminder.addAlarm(EKAlarm(absoluteDate: resetTime))

        do {
            try store.save(reminder, commit: true)
            pendingReminders[key] = reminder.calendarItemIdentifier
        } catch {
            // Non-fatal: reminder creation failed silently
        }
    }

    func completeReminder(for accountName: String, kind: UsageEvent.Kind) async {
        guard authorized else { return }
        let key = reminderKey(accountName: accountName, kind: kind)
        guard let identifier = pendingReminders[key] else { return }

        if let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder {
            reminder.isCompleted = true
            try? store.save(reminder, commit: true)
        }
        pendingReminders.removeValue(forKey: key)
    }

    private func reminderKey(accountName: String, kind: UsageEvent.Kind) -> String {
        "\(accountName)|\(kind.rawValue)"
    }

    private func reminderCalendar(named name: String) -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == name }) {
            return existing
        }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name
        calendar.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
        try? store.saveCalendar(calendar, commit: true)
        return calendar
    }
}
