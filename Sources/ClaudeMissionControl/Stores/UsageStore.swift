import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var states: [UUID: UsageState] = [:]
    @Published private(set) var events: [UsageEvent] = []

    init(accounts: [Account] = []) {
        for account in accounts {
            states[account.id] = .empty
        }
        events = AppSettings.shared.loadEvents()
    }

    func state(for account: Account) -> UsageState {
        states[account.id] ?? .empty
    }

    /// Updates state for the given account and returns any new events generated.
    @discardableResult
    func update(state newState: UsageState, for accountId: UUID) -> [UsageEvent] {
        let previous = states[accountId] ?? .empty
        states[accountId] = newState

        var generated: [UsageEvent] = []

        // 5-hour transitions
        if !previous.isFiveHourLimited && newState.isFiveHourLimited {
            generated.append(UsageEvent(id: UUID(), date: Date(),
                accountName: accountName(for: accountId), kind: .fiveHourLimitReached))
        } else if previous.isFiveHourLimited && !newState.isFiveHourLimited {
            generated.append(UsageEvent(id: UUID(), date: Date(),
                accountName: accountName(for: accountId), kind: .fiveHourLimitRestored))
        }

        // Weekly transitions
        if !previous.isWeeklyLimited && newState.isWeeklyLimited {
            generated.append(UsageEvent(id: UUID(), date: Date(),
                accountName: accountName(for: accountId), kind: .weeklyLimitReached))
        } else if previous.isWeeklyLimited && !newState.isWeeklyLimited {
            generated.append(UsageEvent(id: UUID(), date: Date(),
                accountName: accountName(for: accountId), kind: .weeklyLimitRestored))
        }

        if !generated.isEmpty {
            events = (generated + events).prefix(50).map { $0 }
            AppSettings.shared.saveEvents(events)
        }

        return generated
    }

    func addAccount(id: UUID) {
        if states[id] == nil { states[id] = .empty }
    }

    func removeAccount(id: UUID) {
        states.removeValue(forKey: id)
    }

    var overallStatus: OverallStatus {
        let allLimited = states.values.allSatisfy { $0.isLimited }
        let anyLimited = states.values.contains { $0.isLimited }
        if allLimited && !states.isEmpty { return .allLimited }
        if anyLimited { return .someLimited }
        return .available
    }

    enum OverallStatus { case available, someLimited, allLimited }

    private func accountName(for id: UUID) -> String {
        return id.uuidString.prefix(8).description
    }
}
