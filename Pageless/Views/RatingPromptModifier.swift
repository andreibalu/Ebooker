//
//  RatingPromptModifier.swift
//  Pageless
//
//  Watches for a calm, positive moment and asks StoreKit for a rating. The rules live in
//  `RatingPromptPolicy`; this file gathers the inputs and makes the one call.
//

import CarPlay
import StoreKit
import SwiftData
import SwiftUI

extension View {
    /// Attach once, to the root of the phone UI. CarPlay and background launches have no such view,
    /// so they can never ask.
    func ratingPrompt(isOnboardingComplete: Bool, isPlayerOpen: Bool, isPlaying: Bool) -> some View {
        modifier(RatingPromptModifier(
            isOnboardingComplete: isOnboardingComplete, isPlayerOpen: isPlayerOpen, isPlaying: isPlaying))
    }
}

private struct RatingPromptModifier: ViewModifier {
    let isOnboardingComplete: Bool
    let isPlayerOpen: Bool
    let isPlaying: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @Environment(\.modelContext) private var modelContext
    @State private var isKeyboardVisible = false
    #if DEBUG
    @State private var stubbedRequests = 0
    #endif

    /// Everything the task captures. Any change restarts the watch, which also restarts the settling.
    private struct Trigger: Equatable {
        let scenePhase: ScenePhase
        let isOnboardingComplete: Bool
        let isPlayerOpen: Bool
        let isPlaying: Bool
    }

    private static var pollInterval: Duration {
        #if DEBUG
        if let seconds = E2EFixtures.ratingPollSeconds { return .seconds(seconds) }
        #endif
        return .seconds(2)
    }
    private let store = RatingPromptStore.standard

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                store.noteLaunch()
                #if DEBUG
                E2EFixtures.applyRatingPromptOverrides(to: store)
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .task(id: Trigger(
                scenePhase: scenePhase, isOnboardingComplete: isOnboardingComplete,
                isPlayerOpen: isPlayerOpen, isPlaying: isPlaying)
            ) {
                await watch()
            }
            #if DEBUG
            .overlay(alignment: .topLeading) {
                // Above the status bar's content, so it covers no control.
                if E2EFixtures.ratingStubbed {
                    Text("\(stubbedRequests)")
                        .font(.system(size: 9))
                        .frame(height: 12)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("ratingPrompt.requests")
                        .ignoresSafeArea()
                }
            }
            #endif
    }

    private func watch() async {
        guard scenePhase == .active else { return }
        var settling = RatingPromptSettling()
        var listening: RatingPromptListening?
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
            guard !Task.isCancelled else { return }
            let decision = RatingPromptPolicy.decide(
                history: store.history,
                listening: {
                    if let listening { return listening }
                    let summary = listeningSummary()
                    listening = summary
                    return summary
                },
                situation: situation(),
                appVersion: Self.appVersion,
                now: .now)
            if case .skip(let reason) = decision, reason.isTerminal { return }
            // Nothing in a calm session changes these quickly; a play or pause restarts the watch.
            if case .skip(let reason) = decision, reason == .noPositiveMoment || reason == .installTooNew {
                try? await Task.sleep(for: Self.pollInterval * 14)
                continue
            }
            if settling.observe(decision) {
                request()
                return
            }
        }
    }

    private func situation() -> RatingPromptSituation {
        RatingPromptSituation(
            isOnboardingComplete: isOnboardingComplete,
            isSceneActive: scenePhase == .active,
            // A raised keyboard (search field) counts like a presented sheet.
            isModalPresented: Self.isModalPresented || isKeyboardVisible,
            isPlayerOpen: isPlayerOpen,
            isPlaying: isPlaying,
            isCarPlayConnected: Self.isCarPlayConnected)
    }

    private func listeningSummary() -> RatingPromptListening {
        let now = Date.now
        let start = RatingPromptPolicy.habitWindowStart(now: now)
        let descriptor = FetchDescriptor<ReadingSession>(predicate: #Predicate { $0.date >= start })
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return RatingPromptListening(sessions: sessions.map { ($0.date, $0.minutes) }, now: now)
    }

    private func request() {
        store.recordRequest(version: Self.appVersion)
        #if DEBUG
        // E2E counts the request instead of raising the system sheet, which would block the run.
        if E2EFixtures.ratingStubbed {
            stubbedRequests += 1
            return
        }
        #endif
        requestReview()
    }

    /// SwiftUI sheets, alerts, covers and pickers are all UIKit presentations from the root controller.
    private static var isModalPresented: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }
    }

    private static var isCarPlayConnected: Bool {
        UIApplication.shared.connectedScenes.contains { $0.session.role == .carTemplateApplication }
    }
}
