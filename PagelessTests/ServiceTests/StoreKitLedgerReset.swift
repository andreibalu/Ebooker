//
//  StoreKitLedgerReset.swift
//  PagelessTests
//
//  Not a behavior test: e2e/tests/purchases.e2e.ts runs this first (via
//  `xcodebuild test-without-building -only-testing:PagelessTests/StoreKitLedgerReset`) so every
//  UI purchase starts from an empty local StoreKit ledger. storekitd keeps that ledger in memory,
//  and an `SKTestSession` in this process is the only supported way to clear it.
//
//  It runs only when the e2e suite asks: that run always sets E2E_STOREKIT_FAIL. The reset turns
//  the payment sheet back on, and storekitd can apply that after StoreKitTransactionTests turns it
//  off, so in a full run the next purchase waited on a sheet nobody taps. On Xcode Cloud that hung
//  the first purchase until the 600-second limit on every destination.
//

import Foundation
import StoreKitTest
import Testing

/// The scheme's `Products.storekit`. The app bundle carries the same file, which is the only copy
/// Xcode Cloud test runs can read (the repository path fails there). The repository path stays as a fallback.
enum LocalStoreKitConfiguration {
    static func url() -> URL {
        if let bundled = Bundle.main.url(forResource: "Products", withExtension: "storekit") {
            return bundled
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Pageless/Configuration/Products.storekit")
    }
}

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["E2E_STOREKIT_FAIL"] != nil))
struct StoreKitLedgerReset {
    @Test func clearLocalStoreKitLedger() async throws {
        let configuration = LocalStoreKitConfiguration.url()
        let session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.clearTransactions()
        // Leave the payment sheet enabled: the UI suite confirms and cancels it like a person.
        session.disableDialogs = false
        session.askToBuyEnabled = false
        // storekitd keeps simulated errors after this process exits, so the e2e suite arms a
        // purchase failure through here (xcodebuild forwards TEST_RUNNER_E2E_STOREKIT_FAIL=1).
        // The reset above clears it again for every other run.
        if ProcessInfo.processInfo.environment["E2E_STOREKIT_FAIL"] == "1" {
            try await session.setSimulatedError(
                .generic(.networkError(URLError(.notConnectedToInternet))),
                forAPI: .purchase
            )
        }
        #expect(session.allTransactions().isEmpty)
    }
}
