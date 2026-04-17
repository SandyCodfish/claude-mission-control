// Sources/ClaudeMissionControl/Services/KeychainService.swift
import Foundation
import Security

final class KeychainService: Sendable {
    private let service = "com.claudemissioncontrol.tokens"
    private let cookieHeaderService = "com.claudemissioncontrol.cookieheaders"

    func save(token: String, for accountId: UUID) throws {
        try saveItem(token, service: service, account: accountId.uuidString)
    }

    func getToken(for accountId: UUID) throws -> String? {
        try getItem(service: service, account: accountId.uuidString)
    }

    // Stores/retrieves the full serialized Cookie header (Chrome-imported accounts).
    // Manual-paste accounts leave this absent; the caller falls back to sessionKeyLC.
    func saveCookieHeader(_ header: String, for accountId: UUID) throws {
        try saveItem(header, service: cookieHeaderService, account: accountId.uuidString)
    }

    func getCookieHeader(for accountId: UUID) throws -> String? {
        try getItem(service: cookieHeaderService, account: accountId.uuidString)
    }

    func deleteCookieHeader(for accountId: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: cookieHeaderService,
            kSecAttrAccount as String: accountId.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }

    func delete(for accountId: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId.uuidString
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
        deleteCookieHeader(for: accountId)
    }

    // MARK: - Generic helpers

    private func saveItem(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    private func getItem(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.readFailed(status)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
}
