// Sources/ClaudeMissionControl/Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                generalCard
                appearanceCard
                menuBarCard
            }
            .padding(24)
        }
    }

    private var generalCard: some View {
        VStack(spacing: 0) {
            Text("General").font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 10)
            HStack {
                Text("Show in Dock").font(.system(size: 11))
                Spacer()
                Toggle("", isOn: $settings.showInDock).labelsHidden().toggleStyle(.switch)
            }
            .padding(.vertical, 8)
            Divider()
            HStack {
                Text("Polling interval").font(.system(size: 11))
                Spacer()
                Picker("", selection: $settings.pollingIntervalMinutes) {
                    Text("1 min").tag(1)
                    Text("2 min").tag(2)
                    Text("3 min").tag(3)
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                }
                .pickerStyle(.menu)
                .frame(width: 90)
            }
            .padding(.vertical, 8)
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance").font(.system(size: 11, weight: .semibold))
            HStack(spacing: 10) {
                ForEach(["light", "dark", "system"], id: \.self) { mode in
                    Button { settings.appearance = mode } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(previewColor(for: mode))
                                .frame(width: 40, height: 24)
                            Text(mode.capitalized).font(.system(size: 9))
                        }
                        .padding(8)
                        .background(settings.appearance == mode ? accentColor.opacity(0.1) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(settings.appearance == mode ? accentColor : Color.secondary.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var menuBarCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Color-coded status").font(.system(size: 11))
                Text("Icon tint changes based on account availability")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $settings.colorCodedIcon).labelsHidden().toggleStyle(.switch)
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func previewColor(for mode: String) -> Color {
        switch mode {
        case "light": return Color(hex: "#faf6f0")
        case "dark": return Color(hex: "#1e1e1e")
        default: return Color(hex: "#888888")
        }
    }

    private var cardBackground: Color { colorScheme == .dark ? Color(white: 0.15) : Color(hex: "#f3ede3") }
    private var accentColor: Color { colorScheme == .dark ? Color(hex: "#8b9cf7") : Color(hex: "#6b7bf5") }
}
