// Sources/ClaudeMissionControl/Services/PeakHourService.swift
import Foundation

@MainActor
final class PeakHourService: ObservableObject {
    @Published private(set) var anthropicStatus: String = "Checking..."
    @Published private(set) var windows: [PeakWindow]

    private var statusTask: Task<Void, Never>?

    init(windows: [PeakWindow]? = nil) {
        self.windows = windows ?? AppSettings.shared.peakWindows
    }

    func activeWindow(at date: Date = Date()) -> PeakWindow? {
        windows.first { $0.isActive(at: date) }
    }

    var isAnyWindowActive: Bool { activeWindow() != nil }

    func updateWindows(_ newWindows: [PeakWindow]) {
        windows = newWindows
        AppSettings.shared.peakWindows = newWindows
    }

    func startStatusPolling() {
        statusTask?.cancel()
        statusTask = Task {
            while !Task.isCancelled {
                await self.fetchAnthropicStatus()
                try? await Task.sleep(nanoseconds: 5 * 60 * UInt64(1_000_000_000)) // 5 min
            }
        }
    }

    func stopStatusPolling() { statusTask?.cancel() }

    private func fetchAnthropicStatus() async {
        guard let url = URL(string: "https://status.anthropic.com/api/v2/status.json") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct StatusResponse: Decodable {
                struct Status: Decodable { let description: String }
                let status: Status
            }
            let parsed = try JSONDecoder().decode(StatusResponse.self, from: data)
            anthropicStatus = parsed.status.description
        } catch {
            anthropicStatus = "Unknown"
        }
    }
}
