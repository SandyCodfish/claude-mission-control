// Sources/ClaudeMissionControl/Views/PopoverView.swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var peakHourService: PeakHourService
    @ObservedObject var settings: AppSettings
    var onOpenFullView: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 12)
            accountsSection
            if peakHourService.isAnyWindowActive {
                peakHoursNote
            }
            Divider().padding(.vertical, 10)
            footer
        }
        .padding(18)
        .frame(width: 320)
        .background(backgroundColor)
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack {
            Text("Mission Control")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(primaryText)
            Spacer()
            Text(lastUpdatedLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var accountsSection: some View {
        VStack(spacing: 14) {
            ForEach(accountStore.accounts) { account in
                accountCard(account)
                if account.id != accountStore.accounts.last?.id {
                    Divider()
                }
            }
        }
    }

    private func accountCard(_ account: Account) -> some View {
        let state = usageStore.state(for: account)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(account.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(primaryText)
                Spacer()
                Text(state.isLimited ? "Limited" : "Available")
                    .font(.system(size: 10, weight: state.isLimited ? .medium : .regular))
                    .foregroundStyle(state.isLimited ? limitedColor : .secondary)
            }
            UsageBarView(
                label: "5-hour",
                usage: state.fiveHourUsage,
                resetTime: state.fiveHourResetTime,
                isLimited: state.isFiveHourLimited
            )
            UsageBarView(
                label: "Weekly",
                usage: state.weeklyUsage,
                resetTime: state.weeklyResetTime,
                isLimited: state.isWeeklyLimited
            )
        }
    }

    private var peakHoursNote: some View {
        Group {
            if let window = peakHourService.activeWindow() {
                Text("Peak hours — \(window.name) active, responses may be slower")
                    .font(.system(size: 10))
                    .foregroundStyle(limitedColor)
                    .padding(.top, 10)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(anthropicStatusLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Open Full View") { onOpenFullView() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accentColor)
        }
    }

    // MARK: - Computed

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(hex: "#1e1e1e") : Color(hex: "#faf6f0")
    }
    private var primaryText: Color {
        colorScheme == .dark ? Color(hex: "#e5e5e5") : Color(hex: "#2c2418")
    }
    private var limitedColor: Color {
        colorScheme == .dark ? Color(hex: "#e8a44a") : Color(hex: "#8b5c1a")
    }
    private var accentColor: Color {
        colorScheme == .dark ? Color(hex: "#8b9cf7") : Color(hex: "#6b7bf5")
    }

    private var lastUpdatedLabel: String {
        let states = accountStore.accounts.map { usageStore.state(for: $0) }
        guard let latest = states.map({ $0.lastUpdated }).max() else { return "" }
        let diff = Date().timeIntervalSince(latest)
        if diff < 60 { return "Just now" }
        return "\(Int(diff / 60))m ago"
    }

    private var anthropicStatusLabel: String {
        peakHourService.anthropicStatus
    }
}
