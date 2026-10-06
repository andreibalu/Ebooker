//
//  StoreKitLedgerReset.swift
//  PagelessTests
//
//  Not a behavior test: e2e/tests/purchases.e2e.ts runs this first (via
//  `xcodebuild test-without-building -only-testing:PagelessTests/StoreKitLedgerReset`) so every
//  UI purchase starts from an empty local StoreKit ledger. storekitd keeps that ledger in memory,
//  and an `SKTestSession` in this process is the only supported way to clear it. Running it on its
//  own in a normal suite run is harmless: it clears the same simulator-local test ledger that
//  StoreKitTransactionTests already resets.
//

import Foundation
import StoreKitTest
import Testing

@MainActor
@Suite struct StoreKitLedgerReset {
    @Test func clearLocalStoreKitLedger() async throws {
        let configuration = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Pageless/Configuration/Products.storekit")
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
