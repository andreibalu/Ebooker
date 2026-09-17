//
//  CoffeeTipStore.swift
//  Pageless
//

import Combine
import Foundation
import StoreKit

/// The UI-facing result of trying to buy a coffee.
///
/// A coffee is a consumable, so `.succeeded` is a receipt for this purchase only. It must never
/// be treated as a durable entitlement or used to suppress a later purchase.
enum CoffeeTipPurchaseState: Equatable, Sendable {
    case idle
    case purchasing
    case succeeded
    case cancelled
    case pending
    case unavailable
    case failed
}

/// StoreKit-independent outcomes used to keep purchase-state policy testable.
enum CoffeeTipPurchaseResolution: Equatable, Sendable {
    case verified
    case userCancelled
    case pending
    case unavailable
    case unverified
    case failed
}

/// StoreKit 2 state for the optional, repeatable coffee tip.
///
/// This store deliberately has no entitlement or restore API. The direct purchase result and
/// `Transaction.updates` are both handled on the main actor, while transaction IDs prevent the
/// same verified consumable from being finished twice when those streams overlap.
@MainActor
final class CoffeeTipStore: ObservableObject {
    typealias PurchaseOutcomeProvider = @MainActor () async throws -> CoffeeTipPurchaseResolution

    @Published private(set) var product: Product?
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var loadError: String?
    @Published private(set) var purchaseState: CoffeeTipPurchaseState = .idle
    @Published private(set) var canMakePayments = true
    @Published private(set) var isPurchasing = false

    private let purchaseOutcomeProvider: PurchaseOutcomeProvider?
    private var transactionListener: Task<Void, Never>?
    private var unfinishedTransactionRecovery: Task<Void, Never>?
    private var finishedTransactionIDs: Set<UInt64> = []
    private var verifiedTransactionsDuringPurchase: Set<UInt64> = []

    /// `purchaseOutcomeProvider` and `startTasks` are internal seams for state tests. Production
    /// callers use the default initializer, which talks directly to StoreKit.
    init(
        purchaseOutcomeProvider: PurchaseOutcomeProvider? = nil,
        startTasks: Bool = true
    ) {
        self.purchaseOutcomeProvider = purchaseOutcomeProvider

        guard startTasks else { return }

        transactionListener = Task { [weak self] in
            for await verification in Transaction.updates {
                guard !Task.isCancelled else { return }
                await self?.handleTransactionVerification(verification)
            }
        }
        unfinishedTransactionRecovery = Task { [weak self] in
            for await verification in Transaction.unfinished {
                guard !Task.isCancelled else { return }
                await self?.handleTransactionVerification(verification)
            }
        }
        Task { [weak self] in
            guard let self else { return }
            await self.loadProduct()
            canMakePayments = AppStore.canMakePayments
        }
    }

    deinit {
        transactionListener?.cancel()
        unfinishedTransactionRecovery?.cancel()
    }

    /// StoreKit's localized price. There is intentionally no production fallback price.
    var coffeePriceDisplay: String? {
        product?.displayPrice
    }

    var purchaseButtonTitle: String {
        guard let coffeePriceDisplay else { return "Buy a coffee" }
        return "Buy a coffee \u{2014} \(coffeePriceDisplay)"
    }

    func loadProduct() async {
        guard !isLoadingProduct else { return }
        isLoadingProduct = true
        loadError = nil
        product = nil
        canMakePayments = AppStore.canMakePayments
        defer { isLoadingProduct = false }

        do {
            let products = try await Product.products(for: [CoffeeTipProductID.coffee])
            guard let loadedProduct = products.first(where: {
                $0.id == CoffeeTipProductID.coffee && $0.type == .consumable
            }) else {
                loadError = Self.productUnavailableMessage
                purchaseState = .unavailable
                return
            }
            product = loadedProduct
            if purchaseState == .unavailable {
                purchaseState = .idle
            }
        } catch {
            loadError = Self.productUnavailableMessage
            purchaseState = .unavailable
        }
    }

    func purchase() async {
        guard !isPurchasing else { return }

        isPurchasing = true
        purchaseState = .purchasing
        verifiedTransactionsDuringPurchase.removeAll()
        defer {
            // An approval can arrive through `Transaction.updates` while the direct purchase
            // call is suspended. Apply that verified result after the active call completes so a
            // delayed update cannot be lost behind a `.pending`, cancellation, or thrown error.
            if !verifiedTransactionsDuringPurchase.isEmpty {
                purchaseState = Self.state(for: .verified)
                verifiedTransactionsDuringPurchase.removeAll()
            }
            isPurchasing = false
        }

        // This seam exercises the same state policy without manufacturing StoreKit products in
        // unit tests. It is never set by the app's production initializer.
        if let purchaseOutcomeProvider {
            do {
                purchaseState = Self.state(for: try await purchaseOutcomeProvider())
            } catch {
                purchaseState = .failed
            }
            return
        }

        guard canMakePayments, let product else {
            purchaseState = .unavailable
            return
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    guard transaction.productID == CoffeeTipProductID.coffee else {
                        purchaseState = .failed
                        return
                    }
                    await finishVerifiedTransaction(transaction)
                    purchaseState = Self.state(for: .verified)
                case .unverified:
                    purchaseState = Self.state(for: .unverified)
                }
            case .userCancelled:
                purchaseState = Self.state(for: .userCancelled)
            case .pending:
                purchaseState = Self.state(for: .pending)
            @unknown default:
                purchaseState = Self.state(for: .failed)
            }
        } catch {
            purchaseState = Self.state(for: .failed)
        }
    }

    /// Maps a StoreKit-independent result to the user-visible state. A verified result is the
    /// only state that confirms support; cancellation, pending, unavailable, and errors never
    /// show a thank-you message.
    nonisolated static func state(for resolution: CoffeeTipPurchaseResolution) -> CoffeeTipPurchaseState {
        switch resolution {
        case .verified:
            return .succeeded
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        case .unavailable:
            return .unavailable
        case .unverified, .failed:
            return .failed
        }
    }

    private func handleTransactionVerification(
        _ verification: VerificationResult<StoreKit.Transaction>
    ) async {
        switch verification {
        case .verified(let transaction):
            guard transaction.productID == CoffeeTipProductID.coffee else { return }
            if isPurchasing {
                verifiedTransactionsDuringPurchase.insert(transaction.id)
            }
            await finishVerifiedTransaction(transaction)
            // A delayed approval may arrive through updates after `.pending`. Do not let an
            // unrelated update replace the state of a button press still awaiting its result.
            if !isPurchasing {
                purchaseState = Self.state(for: .verified)
            }
        case .unverified:
            // Never finish or celebrate an unverified consumable.
            return
        }
    }

    private func finishVerifiedTransaction(_ transaction: StoreKit.Transaction) async {
        guard finishedTransactionIDs.insert(transaction.id).inserted else { return }
        await transaction.finish()
    }

    private static let productUnavailableMessage =
        "Coffee support is unavailable right now. Try again later."
}
