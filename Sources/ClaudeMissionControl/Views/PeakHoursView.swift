// Sources/ClaudeMissionControl/Views/PeakHoursView.swift
import SwiftUI

struct PeakHoursView: View {
    @ObservedObject var peakHourService: PeakHourService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusCard
                Text("Custom Peak Windows").font(.system(size: 11, weight: .semibold))
                ForEach(peakHourService.windows) { window in
                    windowRow(window)
                }
                addWindowButton
            }
            .padding(24)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Live Status").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(peakHourService.anthropicStatus)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.green)
            }
            Text("From status.anthropic.com").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func windowRow(_ window: PeakWindow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(window.name).font(.system(size: 11, weight: .medium))
                Text("\(window.startHour):00 – \(window.endHour):00 \(window.timeZoneIdentifier)")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { window.isEnabled },
                set: { enabled in
                    var updated = peakHourService.windows
                    if let idx = updated.firstIndex(where: { $0.id == window.id }) {
                        updated[idx].isEnabled = enabled
                        peakHourService.updateWindows(updated)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(12)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var addWindowButton: some View {
        Button {
            var updated = peakHourService.windows
            updated.append(PeakWindow(name: "New Window", startHour: 9, endHour: 17,
                                      timeZoneIdentifier: TimeZone.current.identifier, isEnabled: false))
            peakHourService.updateWindows(updated)
        } label: {
            HStack {
                Spacer()
                Text("+ Add Peak Window").font(.system(size: 10, weight: .medium)).foregroundStyle(accentColor)
                Spacer()
            }
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.secondary))
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: Color { colorScheme == .dark ? Color(white: 0.15) : Color(hex: "#f3ede3") }
    private var accentColor: Color { colorScheme == .dark ? Color(hex: "#8b9cf7") : Color(hex: "#6b7bf5") }
}
