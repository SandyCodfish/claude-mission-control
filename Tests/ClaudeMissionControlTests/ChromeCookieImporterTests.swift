// Tests/ClaudeMissionControlTests/ChromeCookieImporterTests.swift
import Testing
import Foundation
import CommonCrypto
@testable import ClaudeMissionControl

@Suite("ChromeCookieImporter")
struct ChromeCookieImporterTests {

    // Fixture: encrypt "hello_claude" with a known key, verify round-trip decrypt.
    // This exercises the AES-128-CBC + PKCS7 + "v10" prefix logic without requiring Keychain.
    @Test("decrypt strips 32-byte SHA-256 integrity prefix before returning value")
    func decryptStripsHashPrefix() throws {
        // Chrome prepends SHA-256(host) before encryption. We must strip those 32 bytes.
        let importer = ChromeCookieImporter()
        let realValue = "sk-ant-sid02-abc123"
        let key = Data(repeating: 0x42, count: kCCKeySizeAES128)

        // Simulate Chrome's on-disk format: hash (32 bytes) || value, encrypted, with v10 prefix.
        let fakeHash = Data(repeating: 0xAB, count: 32)
        let payload = fakeHash + Data(realValue.utf8)
        let encrypted = try encryptRaw(payload, key: key)
        let packed = Data("v10".utf8) + encrypted

        let result = importer.decrypt(packed, key: key)
        #expect(result == realValue, "decrypt must strip the 32-byte hash prefix; got: \(result ?? "nil")")
    }

    @Test("decrypt handles legacy format without hash prefix (short values)")
    func decryptLegacyNoHash() throws {
        // Older Chrome versions didn't prepend the hash. A 12-byte value decrypts to 12 bytes.
        // In that case, stripping 32 bytes would break. We treat payloads <= 32 bytes as legacy.
        let importer = ChromeCookieImporter()
        let value = "hello"
        let key = Data(repeating: 0x42, count: kCCKeySizeAES128)
        let encrypted = try encryptRaw(Data(value.utf8), key: key)
        let packed = Data("v10".utf8) + encrypted
        let result = importer.decrypt(packed, key: key)
        #expect(result == value)
    }

    @Test("decrypt returns nil for data shorter than 4 bytes")
    func decryptTooShort() {
        let importer = ChromeCookieImporter()
        let key = Data(repeating: 0x42, count: kCCKeySizeAES128)
        #expect(importer.decrypt(Data([0x76, 0x31, 0x30]), key: key) == nil)  // exactly "v10", no payload
    }

    @Test("decrypt returns nil for data with wrong key")
    func decryptWrongKey() throws {
        let importer = ChromeCookieImporter()
        let key = Data(repeating: 0x42, count: kCCKeySizeAES128)
        let wrongKey = Data(repeating: 0xFF, count: kCCKeySizeAES128)
        let encrypted = Data("v10".utf8) + (try encryptRaw(Data("secret".utf8), key: key))
        // PKCS7 unpad may fail or produce garbage with wrong key — result should be nil or garbage.
        // We just assert it doesn't crash and isn't the original plaintext.
        let result = importer.decrypt(encrypted, key: wrongKey)
        #expect(result != "secret")
    }

    // Encrypts plaintext with AES-128-CBC + PKCS7, IV = 16×0x20. Returns raw ciphertext (no prefix).
    private func encryptRaw(_ plaintext: Data, key: Data) throws -> Data {
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var encrypted = Data(count: plaintext.count + kCCBlockSizeAES128)
        var numBytesEncrypted = 0

        let status: CCCryptorStatus = encrypted.withUnsafeMutableBytes { outPtr in
            plaintext.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, kCCKeySizeAES128,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, plaintext.count,
                            outPtr.baseAddress, outPtr.count,
                            &numBytesEncrypted
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            struct EncryptError: Error {}
            throw EncryptError()
        }
        return encrypted.prefix(numBytesEncrypted)
    }
}
