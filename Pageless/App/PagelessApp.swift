//
//  PagelessApp.swift
//  Pageless
//

import AppIntents
import AVFoundation
import SwiftData
import SwiftUI

@main
struct PagelessApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var aiEntitlementStore = AIEntitlementStore()
    @State private var onboardingManager = OnboardingManager()
    @State private var downloadService = FreeBookDownloadService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.audioPlayer)
                .environmentObject(appDelegate.audioPlayer.equalizer)
                .environmentObject(aiEntitlementStore)
                .environment(onboardingManager)
                .environment(downloadService)
                .onAppear {
                    downloadService.configure(modelContext: appDelegate.modelContainer.mainContext)
                }
                .task {
                    await UnpagedAppShortcuts.updateAppShortcutParameters()
                }
        }
        .modelContainer(appDelegate.modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            handlePendingIntent()
        }
    }

    private func handlePendingIntent() {
        guard UserDefaults.standard.bool(forKey: "intent.playLatestBook") else { return }
        UserDefaults.standard.removeObject(forKey: "intent.playLatestBook")
        let context = appDelegate.modelContainer.mainContext
        var descriptor = FetchDescriptor<Audiobook>(
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let latest = try? context.fetch(descriptor).first else { return }
        let player = appDelegate.audioPlayer
        Task { @MainActor in
            await player.startPlaybackFromSavedProgress(for: latest)
        }
    }
}
