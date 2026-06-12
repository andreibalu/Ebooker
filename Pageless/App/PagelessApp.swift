//
//  PagelessApp.swift
//  Pageless
//

import AppIntents
import SwiftData
import SwiftUI

@main
struct PagelessApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var aiEntitlementStore = AIEntitlementStore()
    @StateObject private var icloudSubscriptionStore = ICloudSubscriptionStore.shared
    @State private var onboardingManager = OnboardingManager()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("forceDarkMode") private var forceDarkMode = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.audioPlayer)
                .environmentObject(appDelegate.audioPlayer.equalizer)
                .environmentObject(aiEntitlementStore)
                .environmentObject(icloudSubscriptionStore)
                .environment(onboardingManager)
                .environment(appDelegate.freeBookDownloader)
                .preferredColorScheme(forceDarkMode ? .dark : nil)
                .onAppear {
                    appDelegate.freeBookDownloader.configure(modelContext: appDelegate.modelContainer.mainContext)
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
        let descriptor = FetchDescriptor<Audiobook>(
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        // Pick the most-recently-played book that's actually in the library on this device —
        // skip cloud-only own orphans and archived (removed) free books. The flags are computed
        // over private backing fields, so they can't be expressed in #Predicate; filter in memory.
        guard let latest = try? context.fetch(descriptor).first(where: {
            ($0.isDownloaded || $0.isFreeBook) && !$0.isArchived
        }) else { return }
        let player = appDelegate.audioPlayer
        Task { @MainActor in
            await player.startPlaybackFromSavedProgress(for: latest)
        }
    }
}
