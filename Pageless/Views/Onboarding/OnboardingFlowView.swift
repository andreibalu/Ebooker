//
//  OnboardingFlowView.swift
//  Pageless
//
//  Root of the welcome flow: a paged vertical scroll of seven full-screen scenes with a floating
//  progress-dot rail. Preference controls bind directly to the app's existing @AppStorage keys, so
//  every choice persists immediately and the final summary stays in sync. "Open Library" marks
//  onboarding complete and routes into the chosen home tab.
//
//  Requirement A — identical on every device/iOS version: a fixed 402pt content column (centered on
//  wider screens), fixed point sizes throughout, a `.dynamicTypeSize(.large)` clamp so accessibility
//  text sizing never reflows layout, and the app's own light/dark theme via `preferredColorScheme`.
//

import AVFoundation
import Speech
import SwiftUI

struct OnboardingFlowView: View {
    let onFinish: (LibraryTab) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("forceDarkMode") private var forceDarkMode = false

    // Live bindings to the same preferences the Settings screen exposes.
    @AppStorage("resumeBacktrackSeconds") private var resumeBacktrackSeconds = ResumeBacktrackOption.oneMinute.rawValue
    @AppStorage("skipBackSeconds") private var skipBackSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("momentBacktrackSeconds") private var momentBacktrackSeconds = MomentBacktrackOption.exact.rawValue

    // Persists the "Free books" home choice so relaunched users open on Free Books and get the
    // reordered tab layout (Favorites / Free Books / Library). Default false = unchanged behavior.
    @AppStorage("startOnFreeBooks") private var startOnFreeBooks = false

    @State private var choice: OnboardingChoice?
    @State private var activeID: Int? = 0

    // Voice permission state for the Permissions scene + final summary. Seeded from the live
    // authorization status so re-runs (Settings → Reset Onboarding) start with the truth.
    @State private var micGranted = AVAudioApplication.shared.recordPermission == .granted
    @State private var speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized

    private static let sceneLabels = ["Start", "Permissions", "Playback", "Your year", "Smart", "iCloud", "Done"]
    private var sceneCount: Int { Self.sceneLabels.count }

    /// A scene is "active" when it's the centered page. `scrollPosition(id:)` can report `nil` before
    /// the first settle, so treat `nil` as scene 0 — otherwise the opening scene's reveal never fires.
    private func isActive(_ index: Int) -> Bool {
        (activeID ?? 0) == index
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                scene(0) {
                    OBChoiceScene(isActive: isActive(0), reduceMotion: reduceMotion,
                                  choice: $choice, onPicked: { jump(to: 1) })
                }
                scene(1) {
                    OBPermissionsScene(isActive: isActive(1), reduceMotion: reduceMotion,
                                       micGranted: $micGranted,
                                       speechGranted: $speechGranted,
                                       onAllGranted: advancePastPermissions)
                }
                scene(2) {
                    OBPlaybackScene(isActive: isActive(2), reduceMotion: reduceMotion,
                                    resume: $resumeBacktrackSeconds,
                                    skipBack: $skipBackSeconds,
                                    skipForward: $skipForwardSeconds,
                                    moment: $momentBacktrackSeconds)
                }
                scene(3) {
                    OBStatsScene(isActive: isActive(3), reduceMotion: reduceMotion)
                }
                scene(4) {
                    OBIntelligenceScene(isActive: isActive(4), reduceMotion: reduceMotion)
                }
                scene(5) {
                    OBCloudScene(isActive: isActive(5), reduceMotion: reduceMotion)
                }
                scene(6) {
                    OBDoneScene(isActive: isActive(6), reduceMotion: reduceMotion,
                                choice: choice,
                                micGranted: micGranted,
                                speechGranted: speechGranted,
                                resume: resumeBacktrackSeconds,
                                skipBack: skipBackSeconds,
                                skipForward: skipForwardSeconds,
                                moment: momentBacktrackSeconds,
                                onOpen: finish)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $activeID, anchor: .center)
        .scrollIndicators(.hidden)
        .background(Color.cream.ignoresSafeArea())
        .overlay(alignment: .trailing) { progressRail }
        .dynamicTypeSize(.large)
        .preferredColorScheme(forceDarkMode ? .dark : nil)
    }

    private func scene<Content: View>(_ index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .containerRelativeFrame(.vertical)
            .id(index)
    }

    // MARK: - Progress rail

    private var progressRail: some View {
        VStack(spacing: 9) {
            ForEach(0..<sceneCount, id: \.self) { i in
                let on = isActive(i)
                Button {
                    jump(to: i)
                } label: {
                    Circle()
                        .fill(on ? OB.accent : OB.fill(0.25))
                        .frame(width: reduceMotion ? 8 : (on ? 8 : 6),
                               height: reduceMotion ? 8 : (on ? 8 : 6))
                        .overlay(
                            Circle()
                                .stroke(OB.accentSoft, lineWidth: 4)
                                .opacity(on ? 1 : 0)
                        )
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.sceneLabels[i])
                .animation(reduceMotion ? .easeOut(duration: 0.2) : OBMotion.selection, value: on)
            }
        }
        .padding(.trailing, 9)
    }

    // MARK: - Navigation

    private func jump(to index: Int) {
        guard !reduceMotion else {
            activeID = index
            return
        }
        withAnimation(Animation.timingCurve(0.77, 0, 0.175, 1, duration: 0.45)) {
            activeID = index
        }
    }

    /// Auto-advance after both permissions land — but only if the user is still on the scene.
    private func advancePastPermissions() {
        guard (activeID ?? 0) == 1 else { return }
        jump(to: 2)
    }

    private func finish() {
        let tab: LibraryTab = (choice == .own) ? .allBooks : .freeBooks
        startOnFreeBooks = (choice == .free)
        onFinish(tab)
    }
}
