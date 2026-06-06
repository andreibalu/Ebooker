//
//  AISettingsView.swift
//  Pageless
//

import StoreKit
import SwiftUI

struct AISettingsView: View {
    /// Closure passed down from `SettingsView` so the "Done" pill in the header
    /// can dismiss the entire sheet (not just pop this pushed view).
    var onDismissSheet: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var aiEntitlement: AIEntitlementStore

    @AppStorage("useLocalAIFeatures") private var useLocalAIFeatures = false
    @AppStorage("useSmartMomentNaming") private var useSmartMomentNaming = false
    @AppStorage("useSmartSummary") private var useSmartSummary = false
    @AppStorage("shortenSummary") private var shortenSummary = false

    private var isSmartNamingAvailable: Bool {
        AppleIntelligenceCapability.isSmartNamingAvailable
    }

    private var availabilityState: AIAvailabilityState {
        AppleIntelligenceCapability.availabilityState
    }

    private var aiSubTogglesDisabled: Bool {
        !useLocalAIFeatures || !aiEntitlement.canUseAIFeatures || !isSmartNamingAvailable
    }

    private var masterToggleDisabled: Bool {
        if aiEntitlement.isUnlocked {
            return !isSmartNamingAvailable
        }
        if aiEntitlement.trialUsesRemaining == 0 {
            return true
        }
        return !isSmartNamingAvailable
    }

    private var masterToggleTitle: String {
        aiEntitlement.isUnlocked ? "Use local AI features" : "Try local AI features"
    }

    private var masterToggleCaption: String {
        if aiEntitlement.isUnlocked {
            return "Enable Apple Intelligence features for this app"
        }
        if aiEntitlement.trialUsesRemaining > 0 {
            return "\(aiEntitlement.trialUsesRemaining) free uses left. Turn off anytime."
        }
        return "Free tries are used up. Unlock below to keep using AI."
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                title: "AI Features",
                titleStyle: .subview,
                backLabel: "Settings",
                onBack: { dismiss() },
                onDone: onDismissSheet
            )
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    paywallCard

                    if availabilityState == .ready, !aiEntitlement.isUnlocked {
                        trialPill
                    }

                    togglesCard

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
        .task {
            await aiEntitlement.loadProduct()
        }
        .onAppear {
            refreshTogglesIfAccessLost()
        }
        .onChange(of: aiEntitlement.trialUsesRemaining) { _, _ in
            refreshTogglesIfAccessLost()
        }
        .onChange(of: aiEntitlement.isUnlocked) { _, _ in
            refreshTogglesIfAccessLost()
        }
        .onChange(of: useLocalAIFeatures) { _, enabled in
            if !enabled {
                useSmartMomentNaming = false
                useSmartSummary = false
                shortenSummary = false
            }
        }
        .onChange(of: useSmartSummary) { _, enabled in
            if !enabled {
                shortenSummary = false
            }
        }
        .alert(
            "Purchase",
            isPresented: Binding(
                get: { aiEntitlement.purchaseError != nil },
                set: { if !$0 { aiEntitlement.purchaseError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { aiEntitlement.purchaseError = nil }
        } message: {
            Text(aiEntitlement.purchaseError ?? "")
        }
        .alert(
            "Restore",
            isPresented: Binding(
                get: { aiEntitlement.restoreError != nil },
                set: { if !$0 { aiEntitlement.restoreError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { aiEntitlement.restoreError = nil }
        } message: {
            Text(aiEntitlement.restoreError ?? "")
        }
    }

    // MARK: - Paywall card

    @ViewBuilder
    private var paywallCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(alignment: .leading, spacing: 12) {
                aiPurchaseBlock
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    @ViewBuilder
    private var aiPurchaseBlock: some View {
        if aiEntitlement.isUnlocked {
            Label("AI features unlocked", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(SettingsDesign.secondaryLabel)
            restorePurchasesButton
        } else {
            switch availabilityState {
            case .ready:
                readyPurchaseBlock
            case .needsActivation:
                needsActivationPurchaseBlock
            case .needsIOSUpgrade:
                needsIOSUpgradePurchaseBlock
            case .unsupportedDevice:
                unsupportedDevicePurchaseBlock
            }
        }
    }

    @ViewBuilder
    private var readyPurchaseBlock: some View {
        Text("Unlock smart moment naming and progress summaries powered by on-device Apple Intelligence.")
            .font(.system(size: 12))
            .foregroundStyle(SettingsDesign.secondaryLabel)
            .lineSpacing(1)

        if let loadError = aiEntitlement.loadError {
            Text(loadError)
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }

        SettingsPrimaryButton(
            title: "Unlock — \(aiEntitlement.unlockPriceDisplay)",
            isLoading: aiEntitlement.isPurchasing,
            isDisabled: aiEntitlement.product == nil
                || aiEntitlement.isLoadingProduct
                || !aiEntitlement.canMakePayments
        ) {
            Task { await aiEntitlement.purchase() }
        }

        restorePurchasesButton
    }

    @ViewBuilder
    private var needsActivationPurchaseBlock: some View {
        Text(AIAvailabilityState.needsActivation.explanation)
            .font(.system(size: 12))
            .foregroundStyle(SettingsDesign.secondaryLabel)

        SettingsPrimaryButton(
            title: "Unlock — \(aiEntitlement.unlockPriceDisplay)",
            isDisabled: true
        ) {}

        restorePurchasesButton
    }

    @ViewBuilder
    private var needsIOSUpgradePurchaseBlock: some View {
        Text(AIAvailabilityState.needsIOSUpgrade.explanation)
            .font(.system(size: 12))
            .foregroundStyle(SettingsDesign.secondaryLabel)

        Text("If you already purchased on another device, use Restore purchases.")
            .font(.system(size: 11))
            .foregroundStyle(SettingsDesign.tertiaryLabel)

        restorePurchasesButton
    }

    @ViewBuilder
    private var unsupportedDevicePurchaseBlock: some View {
        Text(AIAvailabilityState.unsupportedDevice.explanation)
            .font(.system(size: 12))
            .foregroundStyle(SettingsDesign.secondaryLabel)

        Text("If you already purchased on another device, use Restore purchases.")
            .font(.system(size: 11))
            .foregroundStyle(SettingsDesign.tertiaryLabel)

        restorePurchasesButton
    }

    private var restorePurchasesButton: some View {
        SettingsTextLinkButton(title: "Restore purchases") {
            Task { await aiEntitlement.restorePurchases() }
        }
    }

    // MARK: - Trial pill

    private var trialPill: some View {
        Text(
            aiEntitlement.trialUsesRemaining > 0
                ? "\(aiEntitlement.trialUsesRemaining) of \(AIEntitlementStore.initialTrialUses) free uses remaining"
                : "No free uses left"
        )
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SettingsDesign.chipFill, in: Capsule())
    }

    // MARK: - Toggles card

    private var togglesCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(isOn: $useLocalAIFeatures, isDisabled: masterToggleDisabled) {
                    SettingsRowLabel(title: masterToggleTitle, caption: masterToggleCaption)
                }

                if useLocalAIFeatures {
                    dividerInset
                    SettingsToggleRow(isOn: $useSmartMomentNaming, isDisabled: aiSubTogglesDisabled) {
                        SettingsRowLabel(
                            title: "Smart moment naming",
                            caption: "Suggest names for saved moments based on the audio"
                        )
                    }
                    dividerInset
                    SettingsToggleRow(isOn: $useSmartSummary, isDisabled: aiSubTogglesDisabled) {
                        SettingsRowLabel(
                            title: "Smart summary",
                            caption: "Summarize where you left off on the book detail screen"
                        )
                    }
                    if useSmartSummary {
                        dividerInset
                        SettingsToggleRow(isOn: $shortenSummary, isDisabled: aiSubTogglesDisabled) {
                            SettingsRowLabel(
                                title: "Short progress headline",
                                caption: "Replace \u{201C}Your progress\u{201D} with a 3\u{2013}4 word summary"
                            )
                        }
                    }
                }

                if !aiEntitlement.isUnlocked {
                    dividerInset
                    Text("Purchase the AI unlock for unlimited use on a compatible device.")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsDesign.secondaryLabel)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                } else if !isSmartNamingAvailable, let reason = AppleIntelligenceCapability.unavailabilityReason {
                    dividerInset
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsDesign.secondaryLabel)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                }
            }
            .padding(12)
        }
    }

    private var dividerInset: some View {
        SettingsHairline().padding(.leading, 4)
    }

    @ViewBuilder
    private var footerCopy: some View {
        if aiEntitlement.isUnlocked, isSmartNamingAvailable {
            Text("Requires Apple Intelligence and a compatible device. Suggested moment names can be edited before saving.")
                .font(.system(size: 11))
                .foregroundStyle(SettingsDesign.secondaryLabel)
        } else if !aiEntitlement.isUnlocked {
            Text("Unlock once per Apple ID. Restore purchases if you reinstall or use a new device.")
                .font(.system(size: 11))
                .foregroundStyle(SettingsDesign.secondaryLabel)
        }
    }

    private func refreshTogglesIfAccessLost() {
        guard !aiEntitlement.canUseAIFeatures, !aiEntitlement.isUnlocked else { return }
        guard useLocalAIFeatures else { return }
        useLocalAIFeatures = false
        useSmartMomentNaming = false
        useSmartSummary = false
        shortenSummary = false
    }
}

#Preview {
    NavigationStack {
        AISettingsView()
            .environmentObject(AIEntitlementStore())
    }
}
