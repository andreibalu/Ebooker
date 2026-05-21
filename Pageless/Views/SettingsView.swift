//
//  SettingsView.swift
//  Pageless
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    var onRefreshCatalog: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(OnboardingManager.self) private var onboarding
    @EnvironmentObject private var aiEntitlement: AIEntitlementStore
    @Query private var existingAudiobooks: [Audiobook]

    @State private var navigateToAI = false
    @State private var selectedDetent: PresentationDetent = .medium
    @State private var showResetConfirmation = false

    @AppStorage("resumeBacktrackSeconds") private var resumeBacktrackSeconds = ResumeBacktrackOption.oneMinute.rawValue
    @AppStorage("skipBackSeconds") private var skipBackSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("momentBacktrackSeconds") private var momentBacktrackSeconds = MomentBacktrackOption.exact.rawValue
    @AppStorage(IcloudSyncGate.preferenceKey) private var iCloudSyncEnabled = false

    @State private var showRelaunchHint = false
    @State private var hasUbiquityIdentity = IcloudSyncGate.hasUbiquityIdentity()

    /// Only fully-unsupported hardware shows the static "compatible device required" row.
    /// `.needsActivation` and `.needsIOSUpgrade` users still land in `AISettingsView` so they
    /// see actionable guidance there (turn on Apple Intelligence / update to iOS 26).
    private var hideAIEntirely: Bool {
        AppleIntelligenceCapability.availabilityState == .unsupportedDevice
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if hideAIEntirely {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI Features")
                            Text("Requires an Apple Intelligence–compatible device.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .spotlightTarget(.p1DeviceCapability)
                    } else {
                        Button {
                            navigateToAI = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("AI Features")
                                        .foregroundStyle(.primary)
                                    Text(aiTeaserSubline)
                                        .font(.caption)
                                        .foregroundStyle(aiTeaserSublineAccent ? Color.orange : Color.secondary)
                                }
                                Spacer()
                                if aiEntitlement.isUnlocked {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .spotlightTarget(.p1AILink)
                    }
                }

                Section("Playback") {
                    NavigationLink {
                        SettingsDoubleOptionList(
                            navigationTitle: "On Resume",
                            selection: $resumeBacktrackSeconds,
                            options: Array(ResumeBacktrackOption.allCases),
                            rowTitle: \.title
                        )
                    } label: {
                        playbackSettingRow(
                            title: "On Resume",
                            caption: "Rewind a bit when you press play after a break",
                            valueTitle: ResumeBacktrackOption(rawValue: resumeBacktrackSeconds)?.title ?? ""
                        )
                    }

                    NavigationLink {
                        SettingsDoubleOptionList(
                            navigationTitle: "Save Moment Offset",
                            selection: $momentBacktrackSeconds,
                            options: Array(MomentBacktrackOption.allCases),
                            rowTitle: \.title
                        )
                    } label: {
                        playbackSettingRow(
                            title: "Save Moment Offset",
                            caption: "How far back the timestamp is set when you save a moment",
                            valueTitle: MomentBacktrackOption(rawValue: momentBacktrackSeconds)?.title ?? ""
                        )
                    }

                    NavigationLink {
                        SettingsDoubleOptionList(
                            navigationTitle: "Skip Backward",
                            selection: $skipBackSeconds,
                            options: Array(SkipIntervalOption.allCases),
                            rowTitle: \.title
                        )
                    } label: {
                        playbackSettingRow(
                            title: "Skip Backward",
                            caption: "How far the \u{21A9} button jumps back",
                            valueTitle: SkipIntervalOption(rawValue: skipBackSeconds)?.title ?? ""
                        )
                    }

                    NavigationLink {
                        SettingsDoubleOptionList(
                            navigationTitle: "Skip Forward",
                            selection: $skipForwardSeconds,
                            options: Array(SkipIntervalOption.allCases),
                            rowTitle: \.title
                        )
                    } label: {
                        playbackSettingRow(
                            title: "Skip Forward",
                            caption: "How far the \u{21AA} button jumps ahead",
                            valueTitle: SkipIntervalOption(rawValue: skipForwardSeconds)?.title ?? ""
                        )
                    }
                }

                Section {
                    Toggle(isOn: $iCloudSyncEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sync library with iCloud")
                            Text(iCloudCaption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!hasUbiquityIdentity)
                    .onChange(of: iCloudSyncEnabled) { _, _ in
                        showRelaunchHint = true
                    }

                    NavigationLink {
                        CloudLibraryView()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Cloud Library")
                            Text("Restore books that came down from iCloud")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("iCloud Sync")
                } footer: {
                    if !hasUbiquityIdentity {
                        Text("Sign in to iCloud in System Settings to enable sync.")
                    } else if showRelaunchHint {
                        Text("Quit and reopen Unpaged to apply the iCloud change.")
                    } else {
                        Text("Syncs library titles, progress, moments, recaps, EQ, and listening history privately to your iCloud account. Audio files stay on each device.")
                    }
                }

                Section("Free Books") {
                    Button("Refresh Catalog") {
                        onRefreshCatalog?()
                        dismiss()
                    }
                    .foregroundStyle(.primary)
                }

                Section {
                    Button("Reset Onboarding") {
                        showResetConfirmation = true
                    }
                    .foregroundStyle(.primary)
                    .confirmationDialog("Reset Onboarding?", isPresented: $showResetConfirmation) {
                        Button("Reset", role: .destructive) {
                            onboarding.resetOnboarding()
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The onboarding walkthrough will start again from the beginning.")
                    }
                }

                #if DEBUG
                Section("Developer") {
                    Button("Seed Reading Activity · 7 days") {
                        ReadingActivitySeeder.seed(
                            daysTracked: 7,
                            audiobooks: existingAudiobooks,
                            context: modelContext
                        )
                    }
                    .foregroundStyle(.primary)

                    Button("Seed Reading Activity · 30 days") {
                        ReadingActivitySeeder.seed(
                            daysTracked: 30,
                            audiobooks: existingAudiobooks,
                            context: modelContext
                        )
                    }
                    .foregroundStyle(.primary)

                    Button("Seed Reading Activity · 113 days") {
                        ReadingActivitySeeder.seed(
                            daysTracked: 113,
                            audiobooks: existingAudiobooks,
                            context: modelContext
                        )
                    }
                    .foregroundStyle(.primary)

                    Button("Clear Reading Activity", role: .destructive) {
                        ReadingActivitySeeder.clear(context: modelContext)
                    }
                }
                #endif

                Section {
                    Link(destination: LegalURLs.privacyPolicy) {
                        HStack {
                            Text("Privacy Policy")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Link(destination: LegalURLs.termsOfUse) {
                        HStack {
                            Text("Terms of Use")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Free books courtesy of [LibriVox](https://librivox.org) \u{2014} public domain audio recorded by volunteers.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.cream.ignoresSafeArea())
            .navigationDestination(isPresented: $navigateToAI) {
                AISettingsView()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.cream, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await aiEntitlement.loadProduct()
            }
            .onChange(of: onboarding.requestNavigateToAISettings) { _, shouldNavigate in
                if shouldNavigate {
                    navigateToAI = true
                    onboarding.requestNavigateToAISettings = false
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
        .spotlightOverlay(
            onboarding: onboarding,
            totalPhaseSteps: onboarding.totalStepsInPhase,
            currentPhaseIndex: onboarding.currentPhaseIndex
        )
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .onAppear {
            if let step = onboarding.currentStep, step == .p1AILink || step == .p1AIPage || step == .p1DeviceCapability {
                selectedDetent = .large
            }
        }
        .onChange(of: onboarding.currentStep) { _, step in
            if step == .p1AILink || step == .p1DeviceCapability {
                withAnimation { selectedDetent = .large }
            }
        }
    }

    private var aiTeaserSubline: String {
        if aiEntitlement.isUnlocked {
            return "Unlocked"
        }
        if AppleIntelligenceCapability.availabilityState == .needsIOSUpgrade {
            return "Update to iOS 26 to use AI features"
        }
        let price = aiEntitlement.unlockPriceDisplay
        if aiEntitlement.trialUsesRemaining > 0 {
            return "\(aiEntitlement.trialUsesRemaining) free tries left · Unlock for \(price)"
        }
        return "Free tries used up · Unlock for \(price)"
    }

    private var iCloudCaption: String {
        if !hasUbiquityIdentity {
            return "iCloud is not signed in on this device."
        }
        return iCloudSyncEnabled ? "Library data syncs to your iCloud." : "Off — your library stays only on this device."
    }

    private var aiTeaserSublineAccent: Bool {
        if AppleIntelligenceCapability.availabilityState == .needsIOSUpgrade {
            return true
        }
        return !aiEntitlement.isUnlocked && aiEntitlement.trialUsesRemaining == 0
    }

    private func playbackSettingRow(title: String, caption: String, valueTitle: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(valueTitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Cream-styled option list (replaces system navigationLink picker sheet)

private struct SettingsDoubleOptionList<Option: Identifiable & RawRepresentable>: View
    where Option.RawValue == Double {
    let navigationTitle: String
    @Binding var selection: Double
    let options: [Option]
    let rowTitle: KeyPath<Option, String>

    var body: some View {
        List {
            ForEach(options) { option in
                Button {
                    selection = option.rawValue
                } label: {
                    HStack {
                        Text(option[keyPath: rowTitle])
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection == option.rawValue {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .listRowBackground(Color.cardWhite)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.cream.ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.cream, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AIEntitlementStore())
}
