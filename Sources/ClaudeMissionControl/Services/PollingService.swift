// Sources/ClaudeMissionControl/Services/PollingService.swift
import Foundation
import os.log

@MainActor
final class PollingService {
    private static let log = Logger(subsystem: "com.claudemissioncontrol", category: "polling")
    private let apiService: ClaudeAPIService
    private let usageStore: UsageStore
    private let accountStore: AccountStore
    private let reminderService: ReminderService
    private let settings: AppSettings
    private let chromeImporter: ChromeCookieImporter

    private var pollingTask: Task<Void, Never>?
    private var retryTasks: [UUID: Task<Void, Never>] = [:]

    init(
        apiService: ClaudeAPIService = ClaudeAPIService(),
        usageStore: UsageStore,
        accountStore: AccountStore,
        reminderService: ReminderService,
        settings: AppSettings = .shared,
        chromeImporter: ChromeCookieImporter = ChromeCookieImporter()
    ) {
        self.apiService = apiService
        self.usageStore = usageStore
        self.accountStore = accountStore
        self.reminderService = reminderService
        self.settings = settings
        self.chromeImporter = chromeImporter
    }

    func start() {
        stop()
        pollingTask = Task {
            while !Task.isCancelled {
                await poll()
                let interval = UInt64(max(1, settings.pollingIntervalMinutes) * 60) * 1_000_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        retryTasks.values.forEach { $0.cancel() }
        retryTasks.removeAll()
    }

    func pollNow() async { await poll() }

    private func poll() async {
        let accounts = accountStore.accounts.filter { $0.isConnected }
        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask { [self] in
                    await self.fetchAndUpdate(account: account)
                }
            }
        }
    }

    private func fetchAndUpdate(account: Account) async {
        let cookieHeader = resolveCookieHeader(for: account)
        guard let cookieHeader else {
            Self.log.error("fetchAndUpdate: no credentials for accountId=\(account.id.uuidString.prefix(8))")
            return
        }

        do {
            let state = try await apiService.fetchUsage(for: account.id, orgId: account.orgId, cookieHeader: cookieHeader)
            let events = usageStore.update(state: state, for: account.id)
            await handleEvents(events, account: account, state: state)
        } catch APIError.unauthorized {
            Self.log.error("fetchAndUpdate: unauthorized for accountId=\(account.id.uuidString.prefix(8)) — marking disconnected")
            accountStore.markDisconnected(account.id)
        } catch {
            Self.log.error("fetchAndUpdate: error for accountId=\(account.id.uuidString.prefix(8)) — \(error.localizedDescription) — scheduling retry")
            scheduleRetry(for: account)
        }
    }

    private func handleEvents(_ events: [UsageEvent], account: Account, state: UsageState) async {
        for event in events {
            switch event.kind {
            case .fiveHourLimitReached:
                if settings.remindOnFiveHourReset, let resetTime = state.fiveHourResetTime {
                    await reminderService.createResetReminder(
                        for: account.name, kind: .fiveHourLimitRestored,
                        resetTime: resetTime, listName: settings.remindersListName
                    )
                }
                if settings.remindOnLimitReached {
                    await reminderService.createResetReminder(
                        for: account.name, kind: .fiveHourLimitReached,
                        resetTime: Date().addingTimeInterval(1), listName: settings.remindersListName
                    )
                }
            case .fiveHourLimitRestored:
                if settings.remindOnFiveHourReset {
                    await reminderService.completeReminder(for: account.name, kind: .fiveHourLimitRestored)
                }
            case .weeklyLimitReached:
                if settings.remindOnWeeklyReset, let resetTime = state.weeklyResetTime {
                    await reminderService.createResetReminder(
                        for: account.name, kind: .weeklyLimitRestored,
                        resetTime: resetTime, listName: settings.remindersListName
                    )
                }
                if settings.remindOnLimitReached {
                    await reminderService.createResetReminder(
                        for: account.name, kind: .weeklyLimitReached,
                        resetTime: Date().addingTimeInterval(1), listName: settings.remindersListName
                    )
                }
            case .weeklyLimitRestored:
                if settings.remindOnWeeklyReset {
                    await reminderService.completeReminder(for: account.name, kind: .weeklyLimitRestored)
                }
            }
        }
    }

    // For Chrome-imported accounts, re-read cookies from disk on every poll so the session stays
    // valid after Chrome rotates it silently. Falls back to the stored header if the profile is
    // gone or the browser is signed out.
    private func resolveCookieHeader(for account: Account) -> String? {
        if let profile = account.chromeProfileName {
            do {
                if let session = try chromeImporter.readSession(forProfileName: profile) {
                    return session.cookieHeader
                }
                Self.log.error("resolveCookieHeader: Chrome profile \(profile, privacy: .public) is no longer logged in — falling back to stored header")
            } catch {
                Self.log.error("resolveCookieHeader: re-read failed for profile \(profile, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            }
        }
        return accountStore.cookieHeader(for: account)
    }

    private func scheduleRetry(for account: Account) {
        retryTasks[account.id]?.cancel()
        retryTasks[account.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.fetchAndUpdate(account: account)
        }
    }
}
