//
//  UnpagedPlusCard.swift
//  Pageless
//

import StoreKit
import SwiftUI

struct UnpagedPlusCard: View {
    @ObservedObject var store: PlusEntitlementStore
    let includesAI: Bool
    let onAISettings: () -> Void
    let onICloudSettings: () -> Void

    @State private var selectedProductID = PlusProductID.monthly

    private var availableProducts: [Product] {
        PlusProductID.all.compactMap { store.product(for: $0) }
    }

    private var selectedProduct: Product? {
        store.product(for: selectedProductID) ?? availableProducts.first
    }

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 16) {
                heading
                features

                if store.isPlus {
                    entitlementState
                } else if !store.hasLoadedEntitlements {
                    checkingEntitlements
                } else {
                    purchaseOptions
                }

                featureSettingsLinks
            }
            .padding(16)
        }
        .onChange(of: availableProducts.map(\.id)) { _, productIDs in
            if !productIDs.contains(selectedProductID), let first = productIDs.first {
                selectedProductID = first
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.amber.opacity(0.15))
                Image(systemName: "sparkles")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.amber)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("Unpaged Plus")
                    .font(SettingsDesign.displayFont(17, weight: .bold))
                    .foregroundStyle(.primary)
                Text(includesAI
                     ? "A little more from every listen."
                     : "Your library, in sync across devices.")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 9) {
            if includesAI {
                featureRow("Apple Intelligence moment naming and recaps")
            }
            featureRow("iCloud Sync across your devices")
            featureRow("Future Plus features")
        }
    }

    private func featureRow(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.amber)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var entitlementState: some View {
        SettingsHairline()

        if store.isInFreeTrial {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .foregroundStyle(Color.amber)
                Text("\(store.trialDaysRemaining) \(store.trialDaysRemaining == 1 ? "day" : "days") remaining")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.top, 1)
            manageSubscriptionLink
        } else {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.amber)
                Text(store.hasManageableSubscription
                     ? "Unpaged Plus is active"
                     : "Your earlier purchase includes Plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                Spacer(minLength: 0)
            }
            if store.hasManageableSubscription {
                manageSubscriptionLink
            }
        }
    }

    private var checkingEntitlements: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Color.amber)
            Text("Checking purchases…")
                .font(.system(size: 12))
                .foregroundStyle(SettingsDesign.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    private var featureSettingsLinks: some View {
        VStack(spacing: 0) {
            SettingsHairline()
            if includesAI {
                featureSettingsRow(
                    title: "Apple Intelligence",
                    caption: "Choose which local AI features to use",
                    symbol: "sparkles",
                    action: onAISettings
                )
                SettingsHairline().padding(.leading, 34)
            }
            featureSettingsRow(
                title: "iCloud Sync",
                caption: "Manage your library sync settings",
                symbol: "icloud",
                action: onICloudSettings
            )
        }
        .padding(.top, 1)
    }

    private func featureSettingsRow(
        title: String,
        caption: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.amber)
                    .frame(width: 24)
                SettingsRowLabel(title: title, caption: caption)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(SettingsDesign.tertiaryLabel)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var manageSubscriptionLink: some View {
        Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
            HStack(spacing: 6) {
                Text("Manage Subscription")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SettingsDesign.systemBlue)
        }
        .padding(.leading, 27)
    }

    @ViewBuilder
    private var purchaseOptions: some View {
        SettingsHairline()

        if availableProducts.isEmpty {
            unavailablePlans
        } else {
            planPicker

            if let product = selectedProduct {
                purchaseButton(for: product)
                pricingTerms(for: product)
            }

            if let loadError = store.loadError {
                Text(loadError)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                SettingsTextLinkButton(title: "Retry loading plans") {
                    Task { await store.loadProduct() }
                }
            }
            SettingsTextLinkButton(title: "Restore purchases") {
                Task { await store.restorePurchases() }
            }
        }
    }

    @ViewBuilder
    private var unavailablePlans: some View {
        if store.isLoadingProduct {
            HStack(spacing: 10) {
                ProgressView().tint(Color.amber)
                Text("Loading plans…")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)
        } else {
            Text(store.loadError ?? "Unpaged Plus plans are temporarily unavailable.")
                .font(.system(size: 12))
                .foregroundStyle(SettingsDesign.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            retryButton

            SettingsTextLinkButton(title: "Restore purchases") {
                Task { await store.restorePurchases() }
            }
        }
    }

    private var planPicker: some View {
        HStack(spacing: 8) {
            ForEach(availableProducts, id: \.id) { product in
                let isSelected = product.id == (selectedProduct?.id ?? selectedProductID)
                Button {
                    selectedProductID = product.id
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(PlusEntitlementStore.planNameDisplay(for: product))
                            .font(.system(size: 12, weight: .semibold))
                        Text(product.displayPrice)
                            .font(.system(size: 16, weight: .bold))
                        if let offer = PlusEntitlementStore.freeTrialDisplay(for: product) {
                            Text(offer)
                                .font(.system(size: 10, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .foregroundStyle(isSelected ? Color.amber : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        isSelected ? Color.amber.opacity(0.10) : SettingsDesign.chipFill,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.amber.opacity(0.55) : .clear,
                                lineWidth: 1
                            )
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func purchaseButton(for product: Product) -> some View {
        let offer = PlusEntitlementStore.freeTrialDisplay(for: product)
        return Button {
            Task { await store.purchase(productID: product.id) }
        } label: {
            HStack(spacing: 8) {
                if store.isPurchasing && store.purchasingProductID == product.id {
                    ProgressView().tint(.white)
                } else {
                    Text(offer.map { "Try \($0)" } ?? "Subscribe")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Color.amber.opacity(store.canMakePayments ? 1 : 0.5),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(store.isPurchasing || !store.canMakePayments)
    }

    private func pricingTerms(for product: Product) -> some View {
        let offer = PlusEntitlementStore.freeTrialDisplay(for: product)
        let period = PlusEntitlementStore.perPeriodDisplay(for: product)
        let terms = offer == nil
            ? "\(product.displayPrice) per \(period). Cancel anytime."
            : "Then \(product.displayPrice) per \(period). Cancel anytime."
        return Text(terms)
            .font(.system(size: 11))
            .foregroundStyle(SettingsDesign.secondaryLabel)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    private func retryProducts() {
        Task { await store.loadProduct() }
    }

    private var retryButton: some View {
        Button(action: retryProducts) {
            Text("Retry")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.amber, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
