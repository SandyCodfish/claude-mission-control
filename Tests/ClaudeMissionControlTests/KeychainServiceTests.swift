// Tests/ClaudeMissionControlTests/KeychainServiceTests.swift
import Testing
import Foundation
@testable import ClaudeMissionControl

@Suite("KeychainService")
struct KeychainServiceTests {
    @Test("round-trip: save and retrieve token")
    func roundTrip() throws {
        let svc = KeychainService()
        let id = UUID()
        let token = "test-session-token-\(id)"
        try svc.save(token: token, for: id)
        let retrieved = try svc.getToken(for: id)
        #expect(retrieved == token)
        try svc.delete(for: id)
    }

    @Test("returns nil for missing token")
    func missingToken() throws {
        let svc = KeychainService()
        let result = try svc.getToken(for: UUID())
        #expect(result == nil)
    }

    @Test("overwrite existing token")
    func overwrite() throws {
        let svc = KeychainService()
        let id = UUID()
        try svc.save(token: "old", for: id)
        try svc.save(token: "new", for: id)
        let result = try svc.getToken(for: id)
        #expect(result == "new")
        try svc.delete(for: id)
    }
}
