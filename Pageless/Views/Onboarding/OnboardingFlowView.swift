//
//  OnboardingFlowView.swift
//  Pageless
//
//  Root of the welcome flow: a paged vertical scroll of six full-screen scenes with a floating
//  progress-dot rail. Preference controls bind directly to the app's existing @AppStorage keys, so
//  every choice persists immediately and the scene-6 summary stays in sync. "Open Library" marks
//  onboarding complete and routes into the chosen home tab.
//
//  Requirement A — identical on every device/iOS version: a fixed 402pt content column (centered on
//  wider screens), fixed point sizes throughout, a `.dynamicTypeSize(.large)` clamp so accessibility
//  text sizing never reflows layout, and the app's own light/dark theme via `preferredColorScheme`.
//

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

    @State private var choice: OnboardingChoice?
    @State private var activeID: Int? = 0

    private let sceneCount = 6

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
                    OBPlaybackScene(isActive: isActive(1), reduceMotion: reduceMotion,
                                    resume: $resumeBacktrackSeconds,
                                    skipBack: $skipBackSeconds,
                                    skipForward: $skipForwardSeconds,
                                    moment: $momentBacktrackSeconds)
                }
                scene(2) {
                    OBStatsScene(isActive: isActive(2), reduceMotion: reduceMotion)
                }
                scene(3) {
                    OBIntelligenceScene(isActive: isActive(3), reduceMotion: reduceMotion)
                }
                scene(4) {
                    OBCloudScene(isActive: isActive(4), reduceMotion: reduceMotion)
                }
                scene(5) {
                    OBDoneScene(isActive: isActive(5), reduceMotion: reduceMotion,
                                choice: choice,
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
                        .frame(width: on ? 8 : 6, height: on ? 8 : 6)
                        .overlay(
                            Circle()
                                .stroke(OB.accentSoft, lineWidth: on ? 4 : 0)
                        )
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(OBMotion.settle, value: on)
            }
        }
        .padding(.trailing, 9)
    }

    // MARK: - Navigation

    private func jump(to index: Int) {
        withAnimation(.easeInOut(duration: 0.45)) {
            activeID = index
        }
    }

    private func finish() {
        let tab: LibraryTab = (choice == .own) ? .allBooks : .freeBooks
        onFinish(tab)
    }
}
