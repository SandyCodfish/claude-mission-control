// Sources/ClaudeMissionControl/Views/RemindersView.swift
import SwiftUI

struct RemindersView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var accountStore: AccountStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                listPickerCard
                triggersCard
            }
            .padding(24)
        }
    }

    private var listPickerCard: some View {
        HStack {
            Text("Reminders List").font(.system(size: 11, weight: .medium))
            Spacer()
            TextField("List name", text: $settings.remindersListName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .font(.system(size: 11))
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var triggersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notify me when...").font(.system(size: 11, weight: .semibold)).padding(.bottom, 10)
            toggleRow("5-hour limit resets", subtitle: "Reminder when usage is restored", binding: $settings.remindOnFiveHourReset)
            Divider()
            toggleRow("Weekly limit resets", subtitle: "Reminder when weekly usage resets", binding: $settings.remindOnWeeklyReset)
            Divider()
            toggleRow("Limit reached", subtitle: "Immediate reminder when a limit is fully used", binding: $settings.remindOnLimitReached)
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toggleRow(_ title: String, subtitle: String, binding: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11))
                Text(subtitle).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch)
        }
        .padding(.vertical, 8)
    }

    private var cardBackground: Color { colorScheme == .dark ? Color(white: 0.15) : Color(hex: "#f3ede3") }
}
