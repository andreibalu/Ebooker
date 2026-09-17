//
//  BuyMeACoffeeView.swift
//  Pageless
//

import SwiftUI

struct BuyMeACoffeeView: View {
    /// Closure passed down from `SettingsView` so the "Done" pill in the header dismisses the
    /// whole settings sheet instead of only popping this pushed view.
    var onDismissSheet: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coffeeTip: CoffeeTipStore

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                title: "Buy me a coffee",
                titleStyle: .subview,
                backLabel: "Settings",
                onBack: { dismiss() },
                onDone: onDismissSheet
            )
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    introductionCard
                    purchaseCard
                    footerCopy
                    SettingsLegalLinks()
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Color.cream.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .settingsInteractiveBackGesture()
        .task {
            await coffeeTip.loadProduct()
        }
    }

    private var introductionCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.amber.opacity(0.16))
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.amber)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Enjoying Unpaged?")
                            .font(SettingsDesign.displayFont(18, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }

                Text("An optional one-time tip to support Unpaged. It does not unlock features, add content, or provide any other benefit.")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                    .lineSpacing(1.5)
            }
            .padding(16)
        }
    }

    private var purchaseCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(alignment: .leading, spacing: 12) {
                Text("One-time support")
                    .font(SettingsDesign.displayFont(16, weight: .semibold))
                    .foregroundStyle(.primary)

                if let loadError = coffeeTip.loadError {
                    statusText(loadError, color: .red)
                } else if !coffeeTip.canMakePayments {
                    statusText("In-app purchases are unavailable on this device.", color: SettingsDesign.secondaryLabel)
                }

                SettingsPrimaryButton(
                    title: coffeeTip.purchaseButtonTitle,
                    isLoading: coffeeTip.isLoadingProduct || coffeeTip.isPurchasing,
                    isDisabled: coffeeTip.product == nil
                        || coffeeTip.isLoadingProduct
                        || !coffeeTip.canMakePayments
                ) {
                    Task { await coffeeTip.purchase() }
                }

                purchaseStatus

                if coffeeTip.loadError != nil {
                    SettingsTextLinkButton(title: "Try again") {
                        Task { await coffeeTip.loadProduct() }
                    }
                    .disabled(coffeeTip.isLoadingProduct)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var purchaseStatus: some View {
        switch coffeeTip.purchaseState {
        case .idle, .purchasing:
            EmptyView()
        case .succeeded:
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.amber)
                Text("Thank you for the coffee.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
            }
        case .cancelled:
            statusText("Purchase cancelled.", color: SettingsDesign.secondaryLabel)
        case .pending:
            statusText("Purchase is pending approval. We will show thanks after Apple confirms it.", color: SettingsDesign.secondaryLabel)
        case .unavailable:
            if !coffeeTip.isLoadingProduct, coffeeTip.loadError == nil, coffeeTip.canMakePayments {
                statusText("Coffee support is unavailable right now. Try again later.", color: SettingsDesign.secondaryLabel)
            }
        case .failed:
            statusText("The purchase could not be completed. Please try again.", color: SettingsDesign.secondaryLabel)
        }
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(color)
            .lineSpacing(1)
    }

    private var footerCopy: some View {
        Text("The price shown above comes from the App Store and is localized for your region. You can send a coffee again whenever you like. Tips cannot be restored.")
            .font(.system(size: 11))
            .foregroundStyle(SettingsDesign.secondaryLabel)
            .lineSpacing(1.25)
    }
}

#Preview {
    NavigationStack {
        BuyMeACoffeeView()
            .environmentObject(CoffeeTipStore(startTasks: false))
    }
}
