import SwiftData
import SwiftUI

struct WelcomeBackRecapCard: View {
    let audiobook: Audiobook
    let openPlayer: () -> Void
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var plusEntitlement: PlusEntitlementStore
    @AppStorage(AISettingsKey.welcomeBackRecaps.rawValue) private var welcomeBackRecaps = true
    @AppStorage("useLocalAIFeatures") private var useLocalAIFeatures = false
    @State private var viewModel: WelcomeBackRecapViewModel

    init(audiobook: Audiobook, openPlayer: @escaping () -> Void) {
        self.audiobook = audiobook
        self.openPlayer = openPlayer
        _viewModel = State(initialValue: WelcomeBackRecapViewModel(audiobook: audiobook))
    }

    private var enabled: Bool {
        guard #available(iOS 26, *), welcomeBackRecaps else { return false }
        #if DEBUG
        if E2EFixtures.fakeRecapText != nil { return true }
        #endif
        return useLocalAIFeatures && plusEntitlement.isPlus && AppleIntelligenceCapability.isSmartNamingAvailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if enabled, !audiobook.isFinished, viewModel.text != nil || viewModel.isLoading {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Welcome back").font(.headline)
                    if let date = viewModel.returnDate {
                        let days = max(0, Int(Date.now.timeIntervalSince(date) / 86_400))
                        Text("You last listened \(days) days ago").font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("welcomeBack.elapsed")
                    }
                    if viewModel.isLoading {
                        ProgressView("Preparing your recap…")
                            .accessibilityIdentifier("welcomeBack.loading")
                    } else {
                        Text(viewModel.headline ?? "Where you left off")
                            .font(.subheadline.weight(.medium))
                            .accessibilityIdentifier("welcomeBack.headline")
                        Text(viewModel.text ?? "").font(.subheadline)
                            .accessibilityIdentifier("welcomeBack.text")
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { resumeButton; dismissButton }
                        VStack(alignment: .leading) { resumeButton; dismissButton }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 24))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("welcomeBack.card")
            }
            #if DEBUG
            if E2EFixtures.fakeRecapText != nil {
                Text("\(E2EFixtures.welcomeRecapCalls)").font(.caption2)
                    .accessibilityIdentifier("welcomeBack.providerCalls")
            }
            #endif
        }
        .task(id: "\(enabled)-\(audiobook.lastPlayedAt?.timeIntervalSince1970 ?? 0)-\(audiobook.progressUpdatedAt?.timeIntervalSince1970 ?? 0)") {
            await viewModel.prepare(enabled: enabled, modelContext: modelContext)
        }
    }

    private var resumeButton: some View {
        Button("Resume") {
            viewModel.dismiss()
            Task {
                await player.startPlaybackFromSavedProgress(for: audiobook)
                openPlayer()
            }
        }
        .buttonStyle(.borderedProminent).tint(.primary)
        .accessibilityIdentifier("welcomeBack.resume")
    }

    private var dismissButton: some View {
        Button("Not now") { viewModel.dismiss() }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("welcomeBack.notNow")
    }
}
