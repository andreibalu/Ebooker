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
    @EnvironmentObject private var icloudSubscription: ICloudSubscriptionStore
    @Query private var existingAudiobooks: [Audiobook]

    @State private var navigationPath: [SettingsDestination] = []
    @State private var selectedDetent: PresentationDetent = .medium
    @State private var showResetConfirmation = false

    @AppStorage("resumeBacktrackSeconds") private var resumeBacktrackSeconds = ResumeBacktrackOption.oneMinute.rawValue
    @AppStorage("skipBackSeconds") private var skipBackSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("momentBacktrackSeconds") private var momentBacktrackSeconds = MomentBacktrackOption.exact.rawValue
    @AppStorage("forceDarkMode") private var forceDarkMode = false

    private var hideAIEntirely: Bool {
        AppleIntelligenceCapability.availabilityState == .unsupportedDevice
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            rootScreen
                .navigationDestination(for: SettingsDestination.self) { destination in
                    switch destination {
                    case .ai:
                        AISettingsView(onDismissSheet: { dismiss() })
                    case .icloud:
                        ICloudSettingsView(onDismissSheet: { dismiss() })
                    }
                }
        }
        .spotlightOverlay(
            onboarding: onboarding,
            totalPhaseSteps: onboarding.totalStepsInPhase,
            currentPhaseIndex: onboarding.currentPhaseIndex
        )
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .onAppear {
            if let step = onboarding.currentStep,
               step == .p1AILink || step == .p1iCloudSync {
                selectedDetent = .large
            }
        }
        .onChange(of: onboarding.currentStep) { _, step in
            if step == .p1AILink || step == .p1iCloudSync {
                withAnimation { selectedDetent = .large }
            }
        }
    }

    // MARK: - Root screen

    private var rootScreen: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(onDone: { dismiss() })
                .padding(.top, 6)

            ScrollView {
                LazyVStack(spacing: 22) {
                    unlockSection
                    playbackSection
                    librarySection
                    appSection
                    aboutSection
                    #if DEBUG
                    developerSection
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .background(Color.cream.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await aiEntitlement.loadProduct()
            await icloudSubscription.loadProduct()
            await icloudSubscription.refreshEntitlements()
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

    // MARK: - Unlock section (two gradient hero cards)

    private var unlockSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(eyebrow: "Unlock", title: "Make it yours.")

            VStack(spacing: 10) {
                if hideAIEntirely {
                    aiUnsupportedRow
                } else {
                    aiHeroCard
                }
                iCloudHeroCard
            }
        }
    }

    private var aiHeroCard: some View {
        NavigationLink(value: SettingsDestination.ai) {
            HeroCard(
                gradient: LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.10, blue: 0.27),
                        Color(red: 0.09, green: 0.07, blue: 0.21)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                shadowColor: Color(red: 40/255, green: 30/255, blue: 70/255, opacity: 0.18),
                cornerSymbol: "sparkles",
                cornerRotation: 12,
                eyebrowSymbol: "sparkles",
                eyebrowText: "APPLE INTELLIGENCE",
                title: "Smart moments &\nprogress recaps.",
                pill: aiPillView,
                trailingLink: aiTrailingLinkText
            )
        }
        .buttonStyle(.plain)
        .spotlightTarget(.p1AILink)
    }

    @ViewBuilder
    private var aiPillView: some View {
        let label: String = {
            if aiEntitlement.isUnlocked { return "Unlocked" }
            let remaining = aiEntitlement.trialUsesRemaining
            return remaining > 0 ? "\(remaining) free \(remaining == 1 ? "try" : "tries") left" : "Free trial used up"
        }()

        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.18), in: Capsule())
    }

    private var aiTrailingLinkText: String {
        if aiEntitlement.isUnlocked { return "Manage \u{2192}" }
        return "Unlock \(aiEntitlement.unlockPriceDisplay) \u{2192}"
    }

    private var aiUnsupportedRow: some View {
        SettingsCard {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundStyle(SettingsDesign.tertiaryLabel)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Features")
                        .font(.system(size: 15, weight: .medium))
                    Text("Requires an Apple Intelligence\u{2013}compatible device.")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsDesign.secondaryLabel)
                }
                Spacer(minLength: 8)
            }
            .padding(16)
        }
        .spotlightTarget(.p1AILink)
    }

    private var iCloudHeroCard: some View {
        NavigationLink(value: SettingsDestination.icloud) {
            HeroCard(
                gradient: LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.27, blue: 0.46),
                        Color(red: 0.07, green: 0.14, blue: 0.30)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                shadowColor: Color(red: 20/255, green: 40/255, blue: 80/255, opacity: 0.18),
                cornerSymbol: "icloud.fill",
                cornerRotation: -8,
                eyebrowSymbol: "icloud.fill",
                eyebrowText: "ICLOUD SYNC",
                title: "Your library,\neverywhere.",
                pill: iCloudPillView,
                trailingLink: iCloudTrailingLinkText
            )
        }
        .buttonStyle(.plain)
        .spotlightTarget(.p1iCloudSync)
    }

    @ViewBuilder
    private var iCloudPillView: some View {
        if icloudSubscription.isSubscribed {
            Text("ACTIVE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.66)
                .foregroundStyle(Color(red: 0xd6/255, green: 1, blue: 0xe5/255))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(SettingsDesign.systemGreen.opacity(0.28), in: Capsule())
        } else {
            Text(icloudSubscription.trialPeriodDisplay)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.18), in: Capsule())
        }
    }

    private var iCloudTrailingLinkText: String {
        if icloudSubscription.isSubscribed { return "Manage \u{2192}" }
        return "\(icloudSubscription.unlockPriceDisplay)/month \u{2192}"
    }

    // MARK: - Playback section

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(eyebrow: "Playback", title: "Listening preferences.")

            SettingsCard {
                VStack(spacing: 0) {
                    playbackRow(
                        title: "On Resume",
                        caption: "Rewind a bit when you press play after a break",
                        value: ResumeBacktrackOption(rawValue: resumeBacktrackSeconds)?.title ?? "",
                        destination: AnyView(
                            SettingsDoubleOptionList(
                                navigationTitle: "On Resume",
                                selection: $resumeBacktrackSeconds,
                                options: Array(ResumeBacktrackOption.allCases),
                                rowTitle: \.title
                            )
                        ),
                        isLast: false
                    )
                    playbackRow(
                        title: "Save Moment Offset",
                        caption: "How far back the timestamp is set when you save a moment",
                        value: MomentBacktrackOption(rawValue: momentBacktrackSeconds)?.title ?? "",
                        destination: AnyView(
                            SettingsDoubleOptionList(
                                navigationTitle: "Save Moment Offset",
                                selection: $momentBacktrackSeconds,
                                options: Array(MomentBacktrackOption.allCases),
                                rowTitle: \.title
                            )
                        ),
                        isLast: false
                    )
                    playbackRow(
                        title: "Skip Backward",
                        caption: "How far the back button jumps",
                        value: SkipIntervalOption(rawValue: skipBackSeconds)?.title ?? "",
                        destination: AnyView(
                            SettingsDoubleOptionList(
                                navigationTitle: "Skip Backward",
                                selection: $skipBackSeconds,
                                options: Array(SkipIntervalOption.allCases),
                                rowTitle: \.title
                            )
                        ),
                        isLast: false
                    )
                    playbackRow(
                        title: "Skip Forward",
                        caption: "How far the forward button jumps",
                        value: SkipIntervalOption(rawValue: skipForwardSeconds)?.title ?? "",
                        destination: AnyView(
                            SettingsDoubleOptionList(
                                navigationTitle: "Skip Forward",
                                selection: $skipForwardSeconds,
                                options: Array(SkipIntervalOption.allCases),
                                rowTitle: \.title
                            )
                        ),
                        isLast: true
                    )
                }
            }
        }
    }

    private func playbackRow(
        title: String,
        caption: String,
        value: String,
        destination: AnyView,
        isLast: Bool
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsDesign.secondaryLabel)
                        .lineSpacing(1)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(SettingsDesign.tertiaryLabel)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast {
                SettingsHairline()
            }
        }
    }

    // MARK: - Library section

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(eyebrow: "Library", title: "Your collection.")

            SettingsCard {
                VStack(spacing: 0) {
                    actionRow(
                        title: "Refresh Catalog",
                        caption: "Pull the latest books from librivox.org",
                        actionLabel: "Refresh"
                    ) {
                        onRefreshCatalog?()
                        dismiss()
                    }
                    SettingsCardFooter(text: "Free books courtesy of LibriVox \u{2014} public-domain audio recorded by volunteers.")
                }
            }
        }
    }

    // MARK: - App section

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(eyebrow: "App", title: "Tour & appearance.")

            SettingsCard {
                VStack(spacing: 0) {
                    actionRow(
                        title: "Reset Onboarding",
                        caption: "Show the welcome walkthrough again",
                        actionLabel: "Reset"
                    ) {
                        showResetConfirmation = true
                    }
                    .confirmationDialog(
                        "Reset Onboarding?",
                        isPresented: $showResetConfirmation
                    ) {
                        Button("Reset", role: .destructive) {
                            onboarding.resetOnboarding()
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The onboarding walkthrough will start again from the beginning.")
                    }

                    SettingsHairline()

                    HStack(spacing: 12) {
                        SettingsRowLabel(
                            title: "Dark Mode",
                            caption: "Switch the entire app to a darker palette"
                        )
                        Spacer(minLength: 8)
                        Toggle("", isOn: $forceDarkMode)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    // MARK: - About section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(eyebrow: "About", title: "The fine print.")

            SettingsCard {
                VStack(spacing: 0) {
                    linkRow(title: "Privacy Policy", destination: LegalURLs.privacyPolicy, isLast: false)
                    linkRow(title: "Terms of Use", destination: LegalURLs.termsOfUse, isLast: true)
                    SettingsCardFooter(text: aboutFooterText)
                }
            }
        }
    }

    private var aboutFooterText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2"
        return "Unpaged · v\(version) \u{2014} handcrafted for slow listening."
    }

    private func linkRow(title: String, destination: URL, isLast: Bool) -> some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsDesign.tertiaryLabel)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                SettingsHairline()
            }
        }
    }

    // MARK: - Developer section (DEBUG only)

    #if DEBUG
    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(eyebrow: "Developer", title: "Seeders & debug.")

            SettingsCard {
                VStack(spacing: 0) {
                    debugButton("Seed Reading Activity · 7 days") {
                        ReadingActivitySeeder.seed(daysTracked: 7, audiobooks: existingAudiobooks, context: modelContext)
                    }
                    SettingsHairline()
                    debugButton("Seed Reading Activity · 30 days") {
                        ReadingActivitySeeder.seed(daysTracked: 30, audiobooks: existingAudiobooks, context: modelContext)
                    }
                    SettingsHairline()
                    debugButton("Seed Reading Activity · 113 days") {
                        ReadingActivitySeeder.seed(daysTracked: 113, audiobooks: existingAudiobooks, context: modelContext)
                    }
                    SettingsHairline()
                    debugButton("Clear Reading Activity", role: .destructive) {
                        ReadingActivitySeeder.clear(context: modelContext)
                    }
                }
            }
        }
    }

    private func debugButton(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Generic action row (Refresh / Reset)

    private func actionRow(
        title: String,
        caption: String,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            SettingsRowLabel(title: title, caption: caption)
            Spacer(minLength: 8)
            Button(action: action) {
                Text(actionLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(SettingsDesign.pillFill, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Hero card

private struct HeroCard<Pill: View>: View {
    let gradient: LinearGradient
    let shadowColor: Color
    let cornerSymbol: String
    let cornerRotation: Double
    let eyebrowSymbol: String
    let eyebrowText: String
    let title: String
    let pill: Pill
    let trailingLink: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            gradient
            Image(systemName: cornerSymbol)
                .font(.system(size: 140))
                .foregroundStyle(.white)
                .opacity(0.18)
                .rotationEffect(.degrees(cornerRotation))
                .offset(x: 0, y: -10)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(.trailing, -14)
                .padding(.top, -10)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: eyebrowSymbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(eyebrowText)
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 18)

                Text(title)
                    .font(SettingsDesign.displayFont(24, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(.white)
                    .lineSpacing(1)
                    .padding(.top, 8)

                HStack(spacing: 10) {
                    pill
                    Text(trailingLink)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: SettingsDesign.heroCornerRadius, style: .continuous))
        .shadow(color: shadowColor, radius: 20, x: 0, y: 8)
    }
}

// MARK: - Navigation destinations

enum SettingsDestination: Hashable {
    case ai
    case icloud
}

// MARK: - Cream-styled option list (reused destination for playback rows)

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
        .environmentObject(ICloudSubscriptionStore.shared)
        .environment(OnboardingManager())
}
