//
//  AIEntitlementStore.swift
//  Pageless
//

import Combine
import Foundation
import RevenueCat
import StoreKit

/// StoreKit 2 state for the non-consumable AI feature unlock.
@MainActor
final class AIEntitlementStore: ObservableObject {
    private static let trialUsesRemainingKey = "aiTrialUsesRemaining"
    /// Shared free uses across Smart Naming and Smart Summary while on trial.
    static let initialTrialUses = 5

    @Published private(set) var product: Product?
    @Published private(set) var isUnlocked = false
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var loadError: String?
    @Published private(set) var isPurchasing = false
    @Published var purchaseError: String?
    @Published var restoreError: String?

    @Published private(set) var canMakePayments = true
    @Published private(set) var trialUsesRemaining: Int

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.trialUsesRemainingKey) == nil {
            defaults.set(Self.initialTrialUses, forKey: Self.trialUsesRemainingKey)
            trialUsesRemaining = Self.initialTrialUses
        } else {
            trialUsesRemaining = max(0, defaults.integer(forKey: Self.trialUsesRemainingKey))
        }

        Task { await listenForTransactions() }
        Task {
            await refreshEntitlements()
            await loadProduct()
            canMakePayments = AppStore.canMakePayments
        }
    }

    /// Paid unlock, or free tries still available (master toggle in UI gates actual use).
    var canUseAIFeatures: Bool {
        isUnlocked || trialUsesRemaining > 0
    }

    /// Shown in settings when StoreKit price is not loaded yet.
    var unlockPriceDisplay: String {
        product?.displayPrice ?? "3.99"
    }

    /// Call after a successful on-device AI run (naming or recap) while not fully unlocked.
    func consumeTrialUse() {
        guard !isUnlocked else { return }
        guard trialUsesRemaining > 0 else { return }
        trialUsesRemaining -= 1
        UserDefaults.standard.set(trialUsesRemaining, forKey: Self.trialUsesRemainingKey)
        objectWillChange.send()
    }

    func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        loadError = nil
        do {
            let products = try await Product.products(for: [AIProductID.unlock])
            product = products.first
            if product == nil {
                loadError = "Could not load product from the App Store."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var found = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == AIProductID.unlock {
                found = true
                break
            }
        }
        if isUnlocked != found {
            isUnlocked = found
        }
    }

    func purchase() async {
        purchaseError = nil
        guard let product else {
            purchaseError = "Product is not available yet."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            if Purchases.isConfigured {
                _ = try? await Purchases.shared.recordPurchase(result)
            }
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    guard transaction.productID == AIProductID.unlock else { return }
                    await transaction.finish()
                    await refreshEntitlements()
                case .unverified(_, let error):
                    purchaseError = error.localizedDescription
                }
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        restoreError = nil
        do {
            try await AppStore.sync()
            if Purchases.isConfigured {
                _ = try? await Purchases.shared.syncPurchases()
            }
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
                if Purchases.isConfigured {
                    _ = try? await Purchases.shared.syncPurchases()
                }
                await refreshEntitlements()
            case .unverified:
                break
            }
        }
    }
}
