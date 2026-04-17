import Testing
import Foundation
@testable import ClaudeMissionControl

@Suite("UsageStore")
@MainActor
struct UsageStoreTests {
    @Test("starts with empty state for each account")
    func startsEmpty() {
        let account = Account(name: "Test", email: "t@t.com")
        let store = UsageStore(accounts: [account])
        let state = store.state(for: account)
        #expect(state.fiveHourUsage == 0)
        #expect(state.weeklyUsage == 0)
        #expect(!state.isLimited)
    }

    @Test("update sets state for correct account")
    func updateSetsState() {
        let a1 = Account(name: "A1", email: "a1@t.com")
        let a2 = Account(name: "A2", email: "a2@t.com")
        let store = UsageStore(accounts: [a1, a2])
        let newState = UsageState(
            fiveHourUsage: 0.5, fiveHourResetTime: nil,
            weeklyUsage: 0.9, weeklyResetTime: nil,
            lastUpdated: Date()
        )
        store.update(state: newState, for: a1.id)
        #expect(abs(store.state(for: a1).fiveHourUsage - 0.5) < 0.001)
        #expect(store.state(for: a2).fiveHourUsage == 0) // unchanged
    }

    @Test("detects newly limited account")
    func detectsNewlyLimited() {
        let account = Account(name: "Test", email: "t@t.com")
        let store = UsageStore(accounts: [account])
        let state = UsageState(
            fiveHourUsage: 1.0, fiveHourResetTime: Date().addingTimeInterval(3600),
            weeklyUsage: 0.5, weeklyResetTime: nil,
            lastUpdated: Date()
        )
        let events = store.update(state: state, for: account.id)
        #expect(events.contains { $0.kind == .fiveHourLimitReached })
    }

    @Test("detects restored account")
    func detectsRestored() {
        let account = Account(name: "Test", email: "t@t.com")
        let store = UsageStore(accounts: [account])
        // First: set as limited
        let limited = UsageState(fiveHourUsage: 1.0, fiveHourResetTime: nil,
                                  weeklyUsage: 0, weeklyResetTime: nil, lastUpdated: Date())
        _ = store.update(state: limited, for: account.id)
        // Then: restored
        let restored = UsageState(fiveHourUsage: 0.1, fiveHourResetTime: nil,
                                   weeklyUsage: 0, weeklyResetTime: nil, lastUpdated: Date())
        let events = store.update(state: restored, for: account.id)
        #expect(events.contains { $0.kind == .fiveHourLimitRestored })
    }
}
