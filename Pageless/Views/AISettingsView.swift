//
//  AISettingsView.swift
//  Pageless
//

import StoreKit
import SwiftUI

struct AISettingsView: View {
    @Environment(OnboardingManager.self) private var onboarding
    @EnvironmentObject private var aiEntitlement: AIEntitlementStore

    @AppStorage("useLocalAIFeatures") private var useLocalAIFeatures = false
    @AppStorage("useSmartMomentNaming") private var useSmartMomentNaming = false
    @AppStorage("useSmartSummary") private var useSmartSummary = false
    @AppStorage("shortenSummary") private var shortenSummary = false

    private var isSmartNamingAvailable: Bool {
        AppleIntelligenceCapability.isSmartNamingAvailable
    }

    private var canPurchaseOnDevice: Bool {
        AppleIntelligenceCapability.canPurchaseAIUnlockOnThisDevice
    }

    /// Sub-toggles: need master on, runtime AI available, and paid or trial quota left.
    private var aiSubTogglesDisabled: Bool {
        !useLocalAIFeatures || !aiEntitlement.canUseAIFeatures || !isSmartNamingAvailable
    }

    /// Master toggle: when trial is exhausted (not purchased), user cannot turn “try” back on.
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard

                if canPurchaseOnDevice, !aiEntitlement.isUnlocked {
                    trialBadge
                }

                togglesCard
                    .spotlightTarget(.p1AIPage)

                footerCopy
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color.cream.ignoresSafeArea())
        .navigationTitle("AI Features")
        .navigationBarTitleDisplayMode(.inline)
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
            Button("OK", role: .cancel) {
                aiEntitlement.purchaseError = nil
            }
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
            Button("OK", role: .cancel) {
                aiEntitlement.restoreError = nil
            }
        } message: {
            Text(aiEntitlement.restoreError ?? "")
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            aiPurchaseBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var trialBadge: some View {
        HStack {
            Text(
                aiEntitlement.trialUsesRemaining > 0
                    ? "\(aiEntitlement.trialUsesRemaining) of \(AIEntitlementStore.initialTrialUses) free uses remaining"
                    : "No free uses left"
            )
            .font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var togglesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $useLocalAIFeatures) {
                toggleLabel(title: masterToggleTitle, caption: masterToggleCaption)
            }
            .disabled(masterToggleDisabled)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)

            if useLocalAIFeatures {
                Divider()
                    .padding(.leading, 4)

                Toggle(isOn: $useSmartMomentNaming) {
                    toggleLabel(
                        title: "Smart moment naming",
                        caption: "Suggest names for saved moments based on the audio"
                    )
                }
                .disabled(aiSubTogglesDisabled)
                .padding(.vertical, 10)
                .padding(.horizontal, 4)

                Divider()
                    .padding(.leading, 4)

                Toggle(isOn: $useSmartSummary) {
                    toggleLabel(
                        title: "Smart summary",
                        caption: "Summarize where you left off on the book detail screen"
                    )
                }
                .disabled(aiSubTogglesDisabled)
                .padding(.vertical, 10)
                .padding(.horizontal, 4)

                if useSmartSummary {
                    Divider()
                        .padding(.leading, 4)

                    Toggle(isOn: $shortenSummary) {
                        toggleLabel(
                            title: "Short progress headline",
                            caption: "Replace “Your progress” with a 3–4 word summary on one line"
                        )
                    }
                    .disabled(aiSubTogglesDisabled)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                }
            }

            if !aiEntitlement.isUnlocked {
                Divider()
                Text("Purchase the AI unlock for unlimited use on a compatible device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
            } else if !isSmartNamingAvailable, let reason = AppleIntelligenceCapability.unavailabilityReason {
                Divider()
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
            }
        }
        .padding(12)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var footerCopy: some View {
        Group {
            if aiEntitlement.isUnlocked, isSmartNamingAvailable {
                Text("Requires Apple Intelligence and a compatible device. Suggested moment names can be edited before saving.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !aiEntitlement.isUnlocked {
                Text("Unlock once per Apple ID. Restore purchases if you reinstall or use a new device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleLabel(title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func refreshTogglesIfAccessLost() {
        guard !aiEntitlement.canUseAIFeatures, !aiEntitlement.isUnlocked else { return }
        guard useLocalAIFeatures else { return }
        useLocalAIFeatures = false
        useSmartMomentNaming = false
        useSmartSummary = false
        shortenSummary = false
    }

    @ViewBuilder
    private var aiPurchaseBlock: some View {
        if aiEntitlement.isUnlocked {
            Label("AI features unlocked", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            restorePurchasesButton
        } else if canPurchaseOnDevice {
            Text("Unlock smart moment naming and progress summaries powered by on-device Apple Intelligence.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if aiEntitlement.isLoadingProduct {
                ProgressView()
                    .padding(.vertical, 4)
            }

            if let loadError = aiEntitlement.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await aiEntitlement.purchase() }
            } label: {
                if let product = aiEntitlement.product {
                    Text("Unlock — \(product.displayPrice)")
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Unlock — \(aiEntitlement.unlockPriceDisplay)")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(aiEntitlement.product == nil || aiEntitlement.isPurchasing || aiEntitlement.isLoadingProduct)

            restorePurchasesButton
        } else {
            Text(
                "On-device AI requires iOS 18 or later and a compatible device (for example iPhone 15 Pro or newer, or an iPad with an M-series chip). You can’t buy the AI unlock on this device."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("If you already purchased on another device, use Restore purchases.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            restorePurchasesButton
        }
    }

    private var restorePurchasesButton: some View {
        Button("Restore purchases") {
            Task { await aiEntitlement.restorePurchases() }
        }
        .font(.subheadline)
    }
}

#Preview {
    NavigationStack {
        AISettingsView()
            .environmentObject(AIEntitlementStore())
    }
}
