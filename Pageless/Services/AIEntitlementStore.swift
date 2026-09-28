//
//  AIEntitlementStore.swift
//  Pageless
//

import Combine
import StoreKit

/// Read-only view of the legacy non-consumable AI unlock.
/// New purchases are handled by `PlusEntitlementStore`; this reader remains so the legacy
/// entitlement and its restore path stay available.
@MainActor
final class AIEntitlementStore: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published var restoreError: String?

    init() {
        Task { await listenForTransactions() }
        Task { await refreshEntitlements() }
    }

    func refreshEntitlements() async {
        var found = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == AIProductID.unlock,
                  transaction.revocationDate == nil else { continue }
            found = true
            break
        }
        isUnlocked = found
    }

    func restorePurchases() async {
        restoreError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            restoreError = error.localizedDescription
        }
    }

    private func listenForTransactions() async {
        for await verification in Transaction.updates {
            switch verification {
            case .verified(let transaction):
                guard transaction.productID == AIProductID.unlock else { continue }
                await transaction.finish()
                await refreshEntitlements()
            case .unverified:
                break
            }
        }
    }
}
