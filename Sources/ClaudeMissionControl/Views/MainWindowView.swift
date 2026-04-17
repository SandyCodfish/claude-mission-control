// Sources/ClaudeMissionControl/Views/MainWindowView.swift
import SwiftUI

enum SidebarTab: String, CaseIterable {
    case dashboard = "Dashboard"
    case accounts = "Accounts"
    case peakHours = "Peak Hours"
    case reminders = "Reminders"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .dashboard: return "gauge"
        case .accounts: return "person.2"
        case .peakHours: return "clock"
        case .reminders: return "bell"
        case .settings: return "gear"
        }
    }
}

struct MainWindowView: View {
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var peakHourService: PeakHourService
    @ObservedObject var settings: AppSettings
    @State private var selectedTab: SidebarTab = .dashboard

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentArea
        }
        .frame(width: 680, height: 460)
        .background(windowBackground)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mission Control")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            ForEach(SidebarTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .frame(width: 14)
                        Text(tab.rawValue)
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        selectedTab == tab
                            ? RoundedRectangle(cornerRadius: 6).fill(accentColor)
                            : RoundedRectangle(cornerRadius: 6).fill(Color.clear)
                    )
                    .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(width: 170)
        .background(sidebarBackground)
    }

    @ViewBuilder
    private var contentArea: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView(usageStore: usageStore, accountStore: accountStore, peakHourService: peakHourService)
        case .accounts:
            AccountsView(accountStore: accountStore, usageStore: usageStore)
        case .peakHours:
            PeakHoursView(peakHourService: peakHourService)
        case .reminders:
            RemindersView(settings: settings, accountStore: accountStore)
        case .settings:
            SettingsView(settings: settings)
        }
    }

    private var windowBackground: Color { colorScheme == .dark ? Color(hex: "#1e1e1e") : Color(hex: "#faf6f0") }
    private var sidebarBackground: Color { colorScheme == .dark ? Color(white: 0.12) : Color(hex: "#f3ede3") }
    private var accentColor: Color { colorScheme == .dark ? Color(hex: "#8b9cf7") : Color(hex: "#6b7bf5") }
}
