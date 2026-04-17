// Sources/ClaudeMissionControl/App/MenuBarController.swift
import AppKit
import SwiftUI

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var mainWindow: NSWindow?

    // Shared stores — owned here, passed to views
    let accountStore = AccountStore()
    let usageStore: UsageStore
    let peakHourService = PeakHourService()
    let reminderService = ReminderService()
    let settings = AppSettings.shared
    private let pollingService: PollingService
    private var iconTask: Task<Void, Never>?

    init() {
        usageStore = UsageStore(accounts: accountStore.accounts)
        pollingService = PollingService(
            apiService: ClaudeAPIService(),
            usageStore: usageStore,
            accountStore: accountStore,
            reminderService: reminderService
        )
    }

    func setup() {
        setupStatusItem()
        setupPopover()
        pollingService.start()
        peakHourService.startStatusPolling()
        Task { await reminderService.requestAccess() }
        Task { await pollingService.pollNow() }
        updateIconTint()
        iconTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                updateIconTint()
            }
        }
    }

    private func updateIconTint() {
        guard let button = statusItem.button else { return }
        guard settings.colorCodedIcon else {
            button.contentTintColor = nil
            return
        }
        switch usageStore.overallStatus {
        case .available:   button.contentTintColor = .systemGreen
        case .someLimited: button.contentTintColor = .systemOrange
        case .allLimited:  button.contentTintColor = .systemRed
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge", accessibilityDescription: "Claude Mission Control")
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                usageStore: usageStore,
                accountStore: accountStore,
                peakHourService: peakHourService,
                settings: settings,
                onOpenFullView: { [weak self] in
                    self?.openMainWindow()
                    self?.popover.performClose(nil)
                }
            )
        )
    }

    @objc nonisolated private func togglePopover() {
        Task { @MainActor [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            if self.popover.isShown {
                self.popover.performClose(nil)
            } else {
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    func openMainWindow() {
        if let window = mainWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Mission Control"
        window.center()
        window.contentViewController = NSHostingController(
            rootView: MainWindowView(
                usageStore: usageStore,
                accountStore: accountStore,
                peakHourService: peakHourService,
                settings: settings
            )
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        mainWindow = window
    }
}
