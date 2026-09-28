//
//  AISettingsView.swift
//  Pageless
//

import SwiftUI

struct AISettingsView: View {
    /// The Done pill dismisses the entire Settings sheet.
    var onDismissSheet: () -> Void = {}
    /// Returns to the Settings root, where the Unpaged Plus card is shown.
    var onShowPlusCard: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var plusEntitlement: PlusEntitlementStore

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
        !useLocalAIFeatures || !plusEntitlement.isPlus || !isSmartNamingAvailable
    }

    private var masterToggleDisabled: Bool {
        !isSmartNamingAvailable || (!plusEntitlement.isPlus && !useLocalAIFeatures)
    }

    private var masterToggleCaption: String {
        if plusEntitlement.isPlus {
            return "Enable Apple Intelligence features for this app"
        }
        return useLocalAIFeatures
            ? "Turn off local AI features."
            : "Included with Unpaged Plus."
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
                    explanationCard

                    if availabilityState != .ready {
                        availabilityCard
                    }

                    togglesCard

                    if !plusEntitlement.isPlus {
                        plusLinkCard
                    }

                    Text("AI generation and transcription stay on this iPhone. Features require Apple Intelligence and a compatible device.")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsDesign.secondaryLabel)

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
        .task { await plusEntitlement.refreshEntitlements() }
        .onChange(of: useLocalAIFeatures) { _, enabled in
            if !enabled {
                useSmartMomentNaming = false
                useSmartSummary = false
                shortenSummary = false
            }
        }
        .onChange(of: useSmartSummary) { _, enabled in
            if !enabled { shortenSummary = false }
        }
    }

    private var explanationCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Thoughtful moments, picked up where you left off.")
                    .font(SettingsDesign.displayFont(15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Apple Intelligence can suggest names, quotes, characters and moods for saved moments, and recap the passage around your last listening point. Processing runs on-device.")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                    .lineSpacing(1.4)
                Text("These features require an Apple Intelligence–compatible device with Apple Intelligence available.")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var availabilityCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.amber)
                Text(availabilityState.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    private var togglesCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(isOn: $useLocalAIFeatures, isDisabled: masterToggleDisabled) {
                    SettingsRowLabel(
                        title: "Use local AI features",
                        caption: masterToggleCaption
                    )
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

                if !plusEntitlement.isPlus {
                    dividerInset
                    Text("Unpaged Plus includes these features.")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsDesign.secondaryLabel)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                }
            }
            .padding(12)
        }
    }

    private var plusLinkCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Apple Intelligence features are part of Unpaged Plus.")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                SettingsTextLinkButton(title: "View Unpaged Plus") {
                    onShowPlusCard()
                }
            }
            .padding(12)
        }
    }

    private var dividerInset: some View {
        SettingsHairline().padding(.leading, 4)
    }

}

#Preview {
    NavigationStack {
        AISettingsView()
            .environmentObject(PlusEntitlementStore.shared)
    }
}
