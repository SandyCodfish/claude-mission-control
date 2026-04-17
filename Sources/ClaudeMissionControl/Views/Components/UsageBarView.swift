// Sources/ClaudeMissionControl/Views/Components/UsageBarView.swift
import SwiftUI

struct UsageBarView: View {
    let label: String
    let usage: Double          // 0.0–1.0
    let resetTime: Date?
    let isLimited: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(trailingLabel)
                    .font(.system(size: 10, weight: isLimited ? .medium : .regular))
                    .foregroundStyle(isLimited ? limitedColor : .secondary)
            }
            .padding(.bottom, 4)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(trackColor)
                        .frame(height: 10)
                    Rectangle()
                        .fill(fillColor)
                        .frame(width: geo.size.width * min(usage, 1.0), height: 10)
                }
            }
            .frame(height: 10)
        }
    }

    // MARK: - Colors (design spec values)

    @Environment(\.colorScheme) private var colorScheme

    private var fillColor: Color {
        colorScheme == .dark ? Color(hex: "#8b9cf7") : Color(hex: "#6b7bf5")
    }

    private var trackColor: Color {
        colorScheme == .dark ? Color(hex: "#2c2c2c") : Color(hex: "#ebe5da")
    }

    private var limitedColor: Color {
        colorScheme == .dark ? Color(hex: "#e8a44a") : Color(hex: "#8b5c1a")
    }

    // MARK: - Labels

    private var trailingLabel: String {
        if isLimited, let reset = resetTime {
            return "Limited · resets in \(reset.relativeLabel)"
        }
        if isLimited {
            return "Limited"
        }
        if let reset = resetTime {
            return "Resets in \(reset.relativeLabel)"
        }
        return "\(Int(usage * 100))% used"
    }
}

// MARK: - Helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension Date {
    var relativeLabel: String {
        let diff = timeIntervalSinceNow
        if diff <= 0 { return "now" }
        let hours = Int(diff) / 3600
        let mins = (Int(diff) % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}
