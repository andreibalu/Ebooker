//
//  SiriIntentTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

/// Tests that PlayLatestBookIntent sets the UserDefaults flag `PagelessApp` consumes.
@MainActor
struct SiriIntentTests {

    private static let intentFlagKey = "intent.playLatestBook"

    // MARK: - PlayLatestBookIntent

    @Test func intentPerformSetsUserDefaultsFlag() async throws {
        UserDefaults.standard.removeObject(forKey: Self.intentFlagKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.intentFlagKey) }

        let intent = PlayLatestBookIntent()
        _ = try await intent.perform()

        #expect(UserDefaults.standard.bool(forKey: Self.intentFlagKey) == true)
    }

}
