// Sources/ClaudeMissionControl/Services/ChromeCookieImporter.swift
import Foundation
import SQLite3
import CommonCrypto
import Security
import os.log

struct ChromeClaudeSession {
    let profileName: String         // e.g. "Default", "Profile 1"
    let profileDisplayName: String  // human-readable ("Person 1", or email if available)
    let sessionKey: String          // real auth cookie value (sk-ant-sid02-…)
    let lastActiveOrg: String       // UUID string; may be empty
    let cookieHeader: String        // full serialized Cookie header for all claude.ai cookies
}

enum ChromeImportError: LocalizedError {
    case chromeNotInstalled
    case noProfilesWithClaudeSession
    case accessDenied
    case keychain(OSStatus)
    case sqlite(String)
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .chromeNotInstalled:
            return "Chrome is not installed, or no profile directories were found."
        case .noProfilesWithClaudeSession:
            return "No Chrome profile is logged into claude.ai. Log in to Claude in Chrome (use a second Chrome profile for a second account) and try again."
        case .accessDenied:
            return "Cannot read Chrome cookies — grant Full Disk Access to this app in System Settings → Privacy & Security → Full Disk Access."
        case .keychain(let s):
            return "Keychain error reading Chrome Safe Storage key (OSStatus \(s))."
        case .sqlite(let msg):
            return "SQLite error: \(msg)"
        case .decryptionFailed:
            return "Failed to decrypt Chrome cookies."
        }
    }
}

final class ChromeCookieImporter: Sendable {
    private static let log = Logger(subsystem: "com.claudemissioncontrol", category: "chrome-import")

    /// Reads cookies from every Chrome profile on disk and returns one session per profile that is
    /// logged into claude.ai. This supports the "two accounts in two profiles" one-shot flow.
    func importClaudeSessions() throws -> [ChromeClaudeSession] {
        let profiles = try chromeProfiles()
        guard !profiles.isEmpty else { throw ChromeImportError.chromeNotInstalled }

        let key = try chromeSafeStorageKey()

        var sessions: [ChromeClaudeSession] = []
        for profile in profiles {
            do {
                if let session = try readSession(forProfile: profile, key: key) {
                    sessions.append(session)
                }
            } catch let e as ChromeImportError {
                Self.log.error("profile \(profile.name, privacy: .public) import failed: \(e.localizedDescription, privacy: .public)")
                // Keep trying other profiles; surface access-denied if it repeats for all.
                if case .accessDenied = e, profiles.count == 1 { throw e }
            }
        }

        guard !sessions.isEmpty else { throw ChromeImportError.noProfilesWithClaudeSession }
        return sessions
    }

    /// Re-reads cookies for a single known profile. Used by the poller to keep tokens fresh without
    /// re-prompting the user — Chrome rotates the session cookie silently.
    func readSession(forProfileName profileName: String) throws -> ChromeClaudeSession? {
        let profile = ChromeProfile(
            name: profileName,
            cookiesPath: chromeProfilesRoot().appendingPathComponent(profileName).appendingPathComponent("Cookies"),
            displayName: profileName
        )
        let key = try chromeSafeStorageKey()
        return try readSession(forProfile: profile, key: key)
    }

    // MARK: - Per-profile read

    private func readSession(forProfile profile: ChromeProfile, key: Data) throws -> ChromeClaudeSession? {
        guard FileManager.default.fileExists(atPath: profile.cookiesPath.path) else {
            return nil
        }

        // Copy to temp — Chrome holds a write lock while running.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmc-chrome-cookies-\(UUID().uuidString).db")
        do {
            try FileManager.default.copyItem(at: profile.cookiesPath, to: tmp)
        } catch let e as NSError where e.domain == NSPOSIXErrorDomain && e.code == Int(EPERM) {
            throw ChromeImportError.accessDenied
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cookies = try readClaudeCookies(from: tmp, decryptionKey: key)
        Self.log.debug("profile \(profile.name, privacy: .public): \(cookies.count) claude.ai cookies")

        // sessionKey is the real auth cookie (sk-ant-sid02-…). sessionKeyLC is just a Unix
        // timestamp — useless for auth. Skip profiles that aren't logged in.
        guard let sessionKey = cookies["sessionKey"], !sessionKey.isEmpty else {
            return nil
        }

        let header = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        return ChromeClaudeSession(
            profileName: profile.name,
            profileDisplayName: profile.displayName,
            sessionKey: sessionKey,
            lastActiveOrg: cookies["lastActiveOrg"] ?? "",
            cookieHeader: header
        )
    }

    // MARK: - Profile enumeration

    struct ChromeProfile {
        let name: String            // directory name: "Default", "Profile 1", …
        let cookiesPath: URL
        let displayName: String     // human label from Local State if available
    }

    func chromeProfilesRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome")
    }

    private func chromeProfiles() throws -> [ChromeProfile] {
        let root = chromeProfilesRoot()
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }

        // Read Local State to get user-set profile names (falls back to dir name).
        let displayNames = (try? loadProfileDisplayNames(root: root)) ?? [:]

        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let profileDirs = dirs.filter { $0 == "Default" || $0.hasPrefix("Profile ") }

        return profileDirs.map { dirName in
            ChromeProfile(
                name: dirName,
                cookiesPath: root.appendingPathComponent(dirName).appendingPathComponent("Cookies"),
                displayName: displayNames[dirName] ?? dirName
            )
        }
    }

    private func loadProfileDisplayNames(root: URL) throws -> [String: String] {
        let data = try Data(contentsOf: root.appendingPathComponent("Local State"))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let info = profile["info_cache"] as? [String: [String: Any]]
        else { return [:] }
        return info.compactMapValues { $0["name"] as? String }
    }

    // MARK: - SQLite

    func readClaudeCookies(from dbURL: URL, decryptionKey: Data) throws -> [String: String] {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            throw ChromeImportError.sqlite(msg)
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT name, encrypted_value FROM cookies WHERE host_key LIKE '%claude.ai'"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ChromeImportError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var result: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let nameCStr = sqlite3_column_text(stmt, 0) else { continue }
            let name = String(cString: nameCStr)
            let blob = sqlite3_column_blob(stmt, 1)
            let blobLen = Int(sqlite3_column_bytes(stmt, 1))
            guard let blob, blobLen > 3 else { continue }
            let encryptedData = Data(bytes: blob, count: blobLen)
            if let decrypted = decrypt(encryptedData, key: decryptionKey) {
                result[name] = decrypted
            } else {
                Self.log.error("failed to decrypt cookie: \(name, privacy: .public)")
            }
        }
        return result
    }

    // MARK: - AES decrypt

    // Chrome macOS v10 format: 3-byte "v10" prefix + AES-128-CBC ciphertext.
    // Recent Chrome also prepends a 32-byte SHA-256 integrity hash to the plaintext before
    // encryption — if we don't strip it, the returned string is binary garbage and the caller
    // sees a nil decode. Legacy short values (≤32 bytes plaintext) skipped the hash.
    func decrypt(_ data: Data, key: Data) -> String? {
        guard data.count > 3 else { return nil }
        let ciphertext = data.dropFirst(3)
        guard !ciphertext.isEmpty else { return nil }

        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var decrypted = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var numBytesDecrypted = 0

        let status: CCCryptorStatus = decrypted.withUnsafeMutableBytes { outPtr in
            ciphertext.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, kCCKeySizeAES128,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, ciphertext.count,
                            outPtr.baseAddress, outPtr.count,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }

        let plaintext = decrypted.prefix(numBytesDecrypted)
        // Strip 32-byte SHA-256 hash prefix for modern Chrome. Values shorter than or equal to
        // 32 bytes pre-date the hash and are returned as-is.
        let payload: Data = plaintext.count > 32 ? plaintext.dropFirst(32) : plaintext
        return String(data: payload, encoding: .utf8)
    }

    // MARK: - Keychain key derivation

    // Fetches "Chrome Safe Storage" password from Keychain, derives 16-byte AES key via PBKDF2-SHA1.
    // Prompts the user for Keychain access on first call per app run.
    func chromeSafeStorageKey() throws -> Data {
        let serviceName = "Chrome Safe Storage"
        let accountName = "Chrome"

        var passwordLength: UInt32 = 0
        var passwordPtr: UnsafeMutableRawPointer?
        let status = SecKeychainFindGenericPassword(
            nil,
            UInt32(serviceName.utf8.count), serviceName,
            UInt32(accountName.utf8.count), accountName,
            &passwordLength, &passwordPtr,
            nil
        )
        guard status == errSecSuccess, let ptr = passwordPtr else {
            throw ChromeImportError.keychain(status)
        }
        let password = Data(bytes: ptr, count: Int(passwordLength))
        SecKeychainItemFreeContent(nil, passwordPtr)

        let salt = Data("saltysalt".utf8)
        var derivedKey = Data(count: kCCKeySizeAES128)
        let pbkdfStatus: Int32 = derivedKey.withUnsafeMutableBytes { derivedPtr in
            password.withUnsafeBytes { passPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        derivedPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        kCCKeySizeAES128
                    )
                }
            }
        }
        guard pbkdfStatus == kCCSuccess else { throw ChromeImportError.decryptionFailed }
        return derivedKey
    }
}
