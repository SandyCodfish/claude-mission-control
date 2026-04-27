// Sources/ClaudeMissionControl/Stores/AccountStore.swift
import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    private let keychain = KeychainService()
    private let defaultsKey = "accounts"

    init() {
        load()
    }

    func add(_ account: Account, sessionToken: String, cookieHeader: String? = nil) throws {
        try keychain.save(token: sessionToken, for: account.id)
        if let cookieHeader {
            try keychain.saveCookieHeader(cookieHeader, for: account.id)
        }
        var updated = account
        updated.isConnected = true
        accounts.append(updated)
        persist()
    }

    // Returns the full cookie header for use in API requests.
    // Chrome-imported accounts have a stored header; manual-paste accounts fall back to sessionKeyLC.
    func cookieHeader(for account: Account) -> String? {
        if let header = try? keychain.getCookieHeader(for: account.id), !header.isEmpty {
            return header
        }
        guard let token = try? keychain.getToken(for: account.id) else { return nil }
        return "sessionKey=\(token)"
    }

    func update(_ account: Account) {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[idx] = account
        persist()
    }

    func remove(_ account: Account) {
        try? keychain.delete(for: account.id)
        accounts.removeAll { $0.id == account.id }
        persist()
    }

    func sessionToken(for account: Account) -> String? {
        try? keychain.getToken(for: account.id)
    }

    func markDisconnected(_ accountId: UUID) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountId }) else { return }
        accounts[idx].isConnected = false
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([Account].self, from: data)
        else { return }
        accounts = saved
    }
}
