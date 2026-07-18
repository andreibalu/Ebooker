//
//  SettingsView.swift
//  Pageless
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(OnboardingManager.self) private var onboarding
    @EnvironmentObject private var aiEntitlement: AIEntitlementStore
    @EnvironmentObject private var icloudSubscription: ICloudSubscriptionStore
    @Query private var existingAudiobooks: [Audiobook]

    @State private var navigationPath: [SettingsDestination] = []
    @State private var selectedDetent: PresentationDetent = .medium
    @State private var showResetConfirmation = false
    @State private var expandedPicker: PlaybackPicker?

    @AppStorage("resumeBacktrackSeconds") private var resumeBacktrackSeconds = ResumeBacktrackOption.oneMinute.rawValue
    @AppStorage("skipBackSeconds") private var skipBackSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("momentBacktrackSeconds") private var momentBacktrackSeconds = MomentBacktrackOption.exact.rawValue
    @AppStorage("startOnFreeBooks") private var startOnFreeBooks = false
    @AppStorage("forceDarkMode") private var forceDarkMode = false

    /// Identifies which inline playback picker (if any) is currently expanded, so only one
    /// option tray is open at a time.
    private enum PlaybackPicker { case resume, moment, skipBack, skipForward }

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
        .presentationDetents([.medium, .large], selection: $selectedDetent)
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
            Text(icloudSubscription.introOfferDisplay ?? "\(icloudSubscription.unlockPriceDisplay)/month")
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
                    HomeTabRow(startOnFreeBooks: $startOnFreeBooks)

                    SettingsHairline()

                    SettingsInlinePicker(
                        title: "On Resume",
                        caption: "Rewind a bit when you press play after a break",
                        selection: $resumeBacktrackSeconds,
                        options: Array(ResumeBacktrackOption.allCases),
                        rowTitle: \.title,
                        isExpanded: expandedPicker == .resume,
                        onToggle: { togglePicker(.resume) },
                        isLast: false
                    )
                    SettingsInlinePicker(
                        title: "Save Moment Offset",
                        caption: "How far back the timestamp is set when you save a moment",
                        selection: $momentBacktrackSeconds,
                        options: Array(MomentBacktrackOption.allCases),
                        rowTitle: \.title,
                        isExpanded: expandedPicker == .moment,
                        onToggle: { togglePicker(.moment) },
                        isLast: false
                    )
                    SettingsInlinePicker(
                        title: "Skip Backward",
                        caption: "How far the back button jumps",
                        selection: $skipBackSeconds,
                        options: Array(SkipIntervalOption.allCases),
                        rowTitle: \.title,
                        isExpanded: expandedPicker == .skipBack,
                        onToggle: { togglePicker(.skipBack) },
                        isLast: false
                    )
                    SettingsInlinePicker(
                        title: "Skip Forward",
                        caption: "How far the forward button jumps",
                        selection: $skipForwardSeconds,
                        options: Array(SkipIntervalOption.allCases),
                        rowTitle: \.title,
                        isExpanded: expandedPicker == .skipForward,
                        onToggle: { togglePicker(.skipForward) },
                        isLast: true
                    )
                }
            }
        }
    }

    /// Opens the tapped picker (closing any other) or closes it if already open. The whole
    /// transition is animated in one place so the option tray slides rather than pops.
    private func togglePicker(_ picker: PlaybackPicker) {
        withAnimation(.snappy(duration: 0.34, extraBounce: 0.04)) {
            expandedPicker = (expandedPicker == picker) ? nil : picker
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
                            onboarding.reset()
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
                }
            }
        }
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

// MARK: - Inline expanding option picker (replaces the pushed option list)

/// A playback-preference row that reveals its choices in place. Tapping the header slides an
/// option tray open beneath it instead of pushing a new screen — keeping everything inside the
/// detented sheet so the surface never jumps/resizes.
private struct SettingsInlinePicker<Option: Identifiable & RawRepresentable>: View
    where Option.RawValue == Double {
    let title: String
    let caption: String
    @Binding var selection: Double
    let options: [Option]
    let rowTitle: KeyPath<Option, String>
    let isExpanded: Bool
    let onToggle: () -> Void
    let isLast: Bool

    private var currentTitle: String {
        options.first { $0.rawValue == selection }?[keyPath: rowTitle] ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
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
                    Text(currentTitle)
                        .font(.system(size: 14, weight: isExpanded ? .semibold : .regular))
                        .foregroundStyle(isExpanded ? Color.amber : SettingsDesign.secondaryLabel)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(isExpanded ? Color.amber : SettingsDesign.tertiaryLabel)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(options) { option in
                        optionRow(option)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .clipped()
        .overlay(alignment: .bottom) {
            if !isLast {
                SettingsHairline()
            }
        }
    }

    private func optionRow(_ option: Option) -> some View {
        let isSelected = selection == option.rawValue
        return Button {
            selection = option.rawValue
            onToggle()
        } label: {
            HStack(spacing: 10) {
                Text(option[keyPath: rowTitle])
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : SettingsDesign.secondaryLabel)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.amber)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.amber.opacity(0.12) : SettingsDesign.chipFill.opacity(0.5))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Home-tab selector (mirrors the onboarding landing-page choice)

/// A two-segment sliding selector for the launch tab, bound to the same `startOnFreeBooks`
/// `@AppStorage` key the onboarding writes — so the choice stays editable after onboarding.
private struct HomeTabRow: View {
    @Binding var startOnFreeBooks: Bool
    @Namespace private var pill

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Open To")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Text("The library that greets you when you launch Unpaged")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                    .lineSpacing(1)
            }

            HStack(spacing: 4) {
                segment(title: "Free Books", icon: "books.vertical.fill", isOn: startOnFreeBooks) {
                    startOnFreeBooks = true
                }
                segment(title: LibraryTab.allBooks.title, icon: "square.stack.fill", isOn: !startOnFreeBooks) {
                    startOnFreeBooks = false
                }
            }
            .padding(4)
            // Single persistent pill tracking the selected segment's geometry. Keeping it out of
            // the segments means selection changes never insert/remove it, so rapid taps retarget
            // the spring instead of fighting a transition.
            .background {
                Capsule()
                    .fill(Color.amber)
                    .matchedGeometryEffect(
                        id: startOnFreeBooks ? LibraryTab.freeBooks.title : LibraryTab.allBooks.title,
                        in: pill,
                        isSource: false
                    )
            }
            .background(SettingsDesign.chipFill, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func segment(title: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22, extraBounce: 0.04)) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isOn ? .white : SettingsDesign.secondaryLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .matchedGeometryEffect(id: title, in: pill, isSource: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AIEntitlementStore())
        .environmentObject(ICloudSubscriptionStore.shared)
        .environment(OnboardingManager())
}
