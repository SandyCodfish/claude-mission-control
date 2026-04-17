// Sources/ClaudeMissionControl/Views/DashboardView.swift
import SwiftUI

struct DashboardView: View {
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var peakHourService: PeakHourService

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(accountStore.accounts) { account in
                        accountCard(account)
                    }
                    if accountStore.accounts.isEmpty {
                        Text("No accounts added. Go to Accounts to add one.")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                }

                systemStatusCard

                eventsCard
            }
            .padding(24)
        }
    }

    private func accountCard(_ account: Account) -> some View {
        let state = usageStore.state(for: account)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(account.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(state.isLimited ? "Limited" : "Available")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(state.isLimited ? limitedColor : Color.green)
            }
            UsageBarView(label: "5-hour", usage: state.fiveHourUsage,
                         resetTime: state.fiveHourResetTime, isLimited: state.isFiveHourLimited)
            UsageBarView(label: "Weekly", usage: state.weeklyUsage,
                         resetTime: state.weeklyResetTime, isLimited: state.isWeeklyLimited)
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity)
    }

    private var systemStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System Status").font(.system(size: 13, weight: .semibold))
            HStack {
                Text("Anthropic API").font(.system(size: 11))
                Spacer()
                Text(peakHourService.anthropicStatus).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let window = peakHourService.activeWindow() {
                HStack {
                    Text("Peak Hours").font(.system(size: 11))
                    Spacer()
                    Text("Active — \(window.name)").font(.system(size: 10)).foregroundStyle(limitedColor)
                }
            } else {
                HStack {
                    Text("Peak Hours").font(.system(size: 11))
                    Spacer()
                    Text("None active").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Events").font(.system(size: 13, weight: .semibold))
            if usageStore.events.isEmpty {
                Text("No events yet.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(Array(usageStore.events.prefix(10))) { event in
                    HStack {
                        Text(event.date, style: .time)
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Text("\(event.accountName) — \(event.description)")
                            .font(.system(size: 11))
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var cardBackground: Color { colorScheme == .dark ? Color(white: 0.15) : Color(hex: "#f3ede3") }
    private var limitedColor: Color { colorScheme == .dark ? Color(hex: "#e8a44a") : Color(hex: "#8b5c1a") }
}
