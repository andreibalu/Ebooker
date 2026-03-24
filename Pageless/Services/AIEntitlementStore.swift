//
//  AIEntitlementStore.swift
//  Pageless
//

import Combine
import Foundation
import StoreKit

/// StoreKit 2 state for the non-consumable AI feature unlock.
@MainActor
final class AIEntitlementStore: ObservableObject {
    @Published private(set) var product: Product?
    @Published private(set) var isUnlocked = false
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var loadError: String?
    @Published private(set) var isPurchasing = false
    @Published var purchaseError: String?
    @Published var restoreError: String?

    init() {
        Task { await listenForTransactions() }
        Task {
            await refreshEntitlements()
            await loadProduct()
        }
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
