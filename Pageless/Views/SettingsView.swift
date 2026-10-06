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
    @EnvironmentObject private var plusEntitlement: PlusEntitlementStore
    @EnvironmentObject private var coffeeTip: CoffeeTipStore
    /// Called by Audiobookshelf → "Open in Shelves"; the presenter dismisses Settings and switches
    /// the Shelves tab to the server.
    var onOpenAudiobookshelf: () -> Void = {}
    @State private var absAccount = ABSAccount.shared

    init(onOpenAudiobookshelf: @escaping () -> Void = {}) {
        self.onOpenAudiobookshelf = onOpenAudiobookshelf
    }
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
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system

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
                        AISettingsView(
                            onDismissSheet: { dismiss() },
                            onShowPlusCard: showPlusCard
                        )
                    case .icloud:
                        ICloudSettingsView(
                            onDismissSheet: { dismiss() },
                            onShowPlusCard: showPlusCard
                        )
                    case .plus:
                        PlusHubScreen(
                            backLabel: "Settings",
                            onDismissSheet: { dismiss() },
                            onAISettings: { navigationPath.append(.ai) },
                            onICloudSettings: { navigationPath.append(.icloud) },
                            onCloudLibrary: { navigationPath.append(.cloudLibrary) }
                        )
                    case .cloudLibrary:
                        CloudLibraryView()
                    case .coffee:
                        BuyMeACoffeeView(onDismissSheet: { dismiss() })
                    case .audiobookshelf:
                        ABSServerSettingsView(
                            onDismissSheet: { dismiss() },
                            onOpenInShelves: onOpenAudiobookshelf,
                            account: absAccount
                        )
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
                    sourcesSection
                    playbackSection
                    appSection
                    plusSection
                    supportSection
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
            await plusEntitlement.refreshEntitlements()
            await plusEntitlement.loadProduct()
            await coffeeTip.loadProduct()
        }
        .plusPurchaseErrorAlert(store: plusEntitlement)
    }

    /// "View Unpaged Plus" from the AI / iCloud pages: show the Plus hub inside Settings.
    private func showPlusCard() {
        navigationPath = [.plus]
    }

    // MARK: - Unpaged Plus

    /// A plain entry into the Plus hub (the main entry point is the library header's Plus button)
    /// plus the Plus features' own settings pages.
    private var plusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(eyebrow: "Plus", title: "Membership & features.")

            SettingsCard {
                VStack(spacing: 0) {
                    navigationRow(
                        title: "Unpaged Plus",
                        caption: plusEntitlement.isPlus ? "Active" : "Plans, status and restore",
                        symbol: "sparkles",
                        destination: .plus,
                        identifier: "settings.plus"
                    )
                    if !hideAIEntirely {
                        SettingsHairline().padding(.leading, 50)
                        navigationRow(
                            title: "Apple Intelligence",
                            caption: "Choose which local AI features to use",
                            symbol: "wand.and.sparkles",
                            destination: .ai,
                            identifier: "settings.ai"
                        )
                    }
                    SettingsHairline().padding(.leading, 50)
                    navigationRow(
                        title: "iCloud Sync",
                        caption: "Manage your library sync settings",
                        symbol: "icloud",
                        destination: .icloud,
                        identifier: "settings.icloud"
                    )
                }
            }
        }
    }

    private func navigationRow(
        title: String,
        caption: String,
        symbol: String,
        destination: SettingsDestination,
        identifier: String
    ) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.amber)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                SettingsRowLabel(title: title, caption: caption)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SettingsDesign.tertiaryLabel)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(eyebrow: "Support", title: "Support Unpaged.")

            NavigationLink(value: SettingsDestination.coffee) {
                SettingsCard {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.amber.opacity(0.16))
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Color.amber)
                        }
                        .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Buy me a coffee")
                                .font(SettingsDesign.displayFont(16, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Optional one-time support. No features attached.")
                                .font(.system(size: 11))
                                .foregroundStyle(SettingsDesign.secondaryLabel)
                                .lineSpacing(1)
                        }

                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SettingsDesign.tertiaryLabel)
                    }
                    .padding(16)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(eyebrow: "Sources", title: "Your own shelf.")

            NavigationLink(value: SettingsDestination.audiobookshelf) {
                SettingsCard {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(SettingsDesign.chipFill)
                            Image(systemName: "books.vertical")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Audiobookshelf Server")
                                .font(SettingsDesign.displayFont(16, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(absStatusText)
                                .font(.footnote)
                                .foregroundStyle(SettingsDesign.secondaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .accessibilityIdentifier("settings.audiobookshelf.status")
                        }

                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SettingsDesign.tertiaryLabel)
                            .accessibilityHidden(true)
                    }
                    .padding(16)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.audiobookshelf")
        }
    }

    private var absStatusText: String {
        guard let summary = absAccount.summary else { return "Not connected" }
        if let username = summary.username, !username.isEmpty {
            return "\(username) · \(summary.host)"
        }
        return summary.host
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
            SettingsSectionHeader(eyebrow: "App", title: "Appearance & tour.")

            SettingsCard {
                VStack(spacing: 0) {
                    AppearanceRow(appearance: $appearance)

                    SettingsHairline()

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

// MARK: - Navigation destinations

enum SettingsDestination: Hashable {
    case ai
    case icloud
    case coffee
    case audiobookshelf
    case plus
    case cloudLibrary
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
            .accessibilityIdentifier("settings.picker.\(title)")
            .accessibilityValue(currentTitle)

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
                segment(title: "Shelves", icon: "books.vertical.fill", isOn: startOnFreeBooks) {
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
        .accessibilityIdentifier("settings.home.\(title)")
    }
}

// MARK: - Appearance selector

/// System / Light / Dark, styled like `HomeTabRow`. Stored under `AppAppearance.storageKey` and
/// applied at the window by `PagelessApp`, so every option works whatever the phone is set to.
private struct AppearanceRow: View {
    @Binding var appearance: AppAppearance
    @Namespace private var pill

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRowLabel(
                title: "Appearance",
                caption: "Follow your iPhone, or always use light or dark"
            )

            HStack(spacing: 4) {
                ForEach(AppAppearance.allCases) { option in
                    segment(option)
                }
            }
            .padding(4)
            .background {
                Capsule()
                    .fill(Color.amber)
                    .matchedGeometryEffect(id: appearance, in: pill, isSource: false)
            }
            .background(SettingsDesign.chipFill, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func segment(_ option: AppAppearance) -> some View {
        let isOn = appearance == option
        return Button {
            withAnimation(.snappy(duration: 0.22, extraBounce: 0.04)) { appearance = option }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: option.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                Text(option.title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isOn ? .white : SettingsDesign.secondaryLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .matchedGeometryEffect(id: option, in: pill, isSource: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.appearance.\(option.rawValue)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview {
    SettingsView()
        .environmentObject(PlusEntitlementStore.shared)
        .environmentObject(CoffeeTipStore(startTasks: false))
        .environment(OnboardingManager())
}
