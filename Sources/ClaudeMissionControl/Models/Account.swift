// Sources/ClaudeMissionControl/Models/Account.swift
import Foundation

struct Account: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String        // "Work", "Personal"
    var email: String       // display only
    var orgId: String
    var isConnected: Bool
    // Chrome profile directory name ("Default", "Profile 1", …) for accounts imported from Chrome.
    // When set, the poller re-reads fresh cookies from this profile on every poll so the session
    // stays valid after Chrome rotates it. nil for manual-paste accounts.
    var chromeProfileName: String?
    // Session token is NOT stored here.
    // Use KeychainService.getToken(for: account.id) at request time.

    init(id: UUID = UUID(), name: String, email: String, orgId: String = "", isConnected: Bool = false, chromeProfileName: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.orgId = orgId
        self.isConnected = isConnected
        self.chromeProfileName = chromeProfileName
    }
}
