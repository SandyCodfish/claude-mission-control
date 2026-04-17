// Sources/ClaudeMissionControl/Views/AccountsView.swift
import AppKit
import SwiftUI

struct AccountsView: View {
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var usageStore: UsageStore
    @State private var authError: String?
    @State private var showManualSetup = false
    @State private var isImporting = false
    @Environment(\.colorScheme) private var colorScheme

    // Manual setup fields
    @State private var manualName = ""
    @State private var manualToken = ""
    @State private var manualOrgId = ""

    private let apiService = ClaudeAPIService()
    private let importer = ChromeCookieImporter()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(accountStore.accounts) { account in
                    accountCard(account)
                }
                if showManualSetup {
                    manualSetupCard
                } else {
                    addAccountButtons
                }
                if let error = authError {
                    Text(error).font(.system(size: 10)).foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }

    private func accountCard(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(account.name).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(account.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(account.isConnected ? .green : .orange)
            }
            Text(account.email).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Rename") { rename(account) }
                    .buttonStyle(.plain).font(.system(size: 9, weight: .medium)).foregroundStyle(accentColor)
                Button("Update Token") { updateToken(account) }
                    .buttonStyle(.plain).font(.system(size: 9, weight: .medium)).foregroundStyle(accentColor)
                Button("Remove") { remove(account) }
                    .buttonStyle(.plain).font(.system(size: 9, weight: .medium)).foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Add Account Buttons

    private var addAccountButtons: some View {
        VStack(spacing: 8) {
            Button {
                importFromChrome()
            } label: {
                HStack {
                    Spacer()
                    if isImporting {
                        ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                        Text("Importing from Chrome…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(accentColor)
                    } else {
                        Text("+ Import from Chrome")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(accentColor)
                    }
                    Spacer()
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(.secondary))
            }
            .buttonStyle(.plain)
            .disabled(isImporting)

            Button("…or paste cookies manually") {
                showManualSetup = true
                manualName = "Account \(accountStore.accounts.count + 1)"
            }
            .buttonStyle(.plain)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Manual Setup Card

    private var manualSetupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Account").font(.system(size: 12, weight: .semibold))
            Text("Paste values from DevTools (Application → Cookies on claude.ai)")
                .font(.system(size: 9)).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                labeledField("Name", placeholder: "e.g. Work", text: $manualName)
                labeledField("Session Token", placeholder: "sessionKey cookie value", text: $manualToken)
                labeledField("Org UUID", placeholder: "lastActiveOrg cookie value", text: $manualOrgId)
            }

            HStack {
                Button("Cancel") {
                    showManualSetup = false
                    clearManualFields()
                }
                .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)

                Spacer()

                Button("Save") { Task { await saveManualAccount() } }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(accentColor)
                    .disabled(manualToken.isEmpty || manualOrgId.isEmpty)
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func labeledField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
        }
    }

    // MARK: - Actions

    private func importFromChrome() {
        authError = nil
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                let sessions = try importer.importClaudeSessions()

                // Skip profiles that are already imported (match by profile name).
                let existingProfiles = Set(accountStore.accounts.compactMap { $0.chromeProfileName })
                let newSessions = sessions.filter { !existingProfiles.contains($0.profileName) }

                guard !newSessions.isEmpty else {
                    authError = "All Chrome profiles logged into claude.ai are already imported."
                    return
                }

                var added = 0
                var lastError: String?
                for session in newSessions {
                    do {
                        try await addChromeSession(session)
                        added += 1
                    } catch {
                        lastError = "\(session.profileDisplayName): \(error.localizedDescription)"
                    }
                }
                if added == 0, let lastError {
                    authError = lastError
                } else if let lastError {
                    authError = "Imported \(added) of \(newSessions.count) profiles. \(lastError)"
                }
            } catch APIError.vpnBlocked {
                authError = "VPN detected — QUIC datagrams exceed tunnel MTU. Disconnect VPN and retry."
            } catch {
                authError = error.localizedDescription
            }
        }
    }

    private func addChromeSession(_ session: ChromeClaudeSession) async throws {
        // Preflight: verify credentials work before persisting. Prefer the cookie's lastActiveOrg
        // (same profile, same session — they always match) and fall back to /api/organizations.
        let orgId: String
        if !session.lastActiveOrg.isEmpty {
            orgId = session.lastActiveOrg
        } else {
            orgId = try await apiService.fetchOrgId(cookieHeader: session.cookieHeader)
        }
        _ = try await apiService.fetchUsage(for: UUID(), orgId: orgId, cookieHeader: session.cookieHeader)

        let name = session.profileDisplayName.isEmpty
            ? "Account \(accountStore.accounts.count + 1)"
            : session.profileDisplayName
        let account = Account(name: name, email: "", orgId: orgId, chromeProfileName: session.profileName)
        try accountStore.add(account, sessionToken: session.sessionKey, cookieHeader: session.cookieHeader)
        usageStore.addAccount(id: account.id)
    }

    private func saveManualAccount() async {
        authError = nil
        let name = manualName.isEmpty ? "Account \(accountStore.accounts.count + 1)" : manualName
        let orgId = manualOrgId.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let cookieHeader = "sessionKey=\(token)"

        // Preflight: verify before persisting so the user gets immediate feedback on bad credentials.
        do {
            _ = try await apiService.fetchUsage(for: UUID(), orgId: orgId, cookieHeader: cookieHeader)
        } catch APIError.unauthorized {
            authError = "Unauthorized — session token may be stale. Copy a fresh sessionKey from DevTools."
            return
        } catch APIError.vpnBlocked {
            authError = "VPN detected — QUIC datagrams exceed tunnel MTU. Disconnect VPN and retry."
            return
        } catch APIError.invalidURL {
            authError = "Invalid Org UUID — make sure you copied lastActiveOrg correctly."
            return
        } catch {
            authError = "Could not verify account: \(error.localizedDescription)"
            return
        }

        let account = Account(name: name, email: "", orgId: orgId)
        do {
            try accountStore.add(account, sessionToken: token)
            usageStore.addAccount(id: account.id)
            showManualSetup = false
            clearManualFields()
        } catch {
            authError = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func updateToken(_ account: Account) {
        let alert = NSAlert()
        alert.messageText = "Update Session Token"
        alert.informativeText = "Paste the sessionKey cookie value from DevTools."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.placeholderString = "sessionKey cookie value"
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            let token = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return }
            do {
                try accountStore.add(account, sessionToken: token)
            } catch {
                authError = "Failed to update token: \(error.localizedDescription)"
            }
        }
    }

    private func rename(_ account: Account) {
        let alert = NSAlert()
        alert.messageText = "Rename Account"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = account.name
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            var updated = account
            updated.name = field.stringValue.isEmpty ? account.name : field.stringValue
            accountStore.update(updated)
        }
    }

    private func remove(_ account: Account) {
        accountStore.remove(account)
        usageStore.removeAccount(id: account.id)
    }

    private func clearManualFields() {
        manualName = ""
        manualToken = ""
        manualOrgId = ""
    }

    private var cardBackground: Color { colorScheme == .dark ? Color(white: 0.15) : Color(hex: "#f3ede3") }
    private var accentColor: Color { colorScheme == .dark ? Color(hex: "#8b9cf7") : Color(hex: "#6b7bf5") }
}
