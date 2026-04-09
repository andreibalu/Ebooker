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
    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var aiEntitlementStore = AIEntitlementStore()
    @State private var onboardingManager = OnboardingManager()
    @State private var downloadService = FreeBookDownloadService()
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Audiobook.self,
            AudioTrack.self,
            Moment.self,
        ])

        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let storeURL = supportURL.appendingPathComponent("default.store")

        let modelConfiguration = ModelConfiguration(url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioPlayer)
                .environmentObject(aiEntitlementStore)
                .environment(onboardingManager)
                .environment(downloadService)
                .onAppear {
                    appDelegate.modelContainer = sharedModelContainer
                    appDelegate.audioPlayer = audioPlayer
                    downloadService.configure(modelContext: sharedModelContainer.mainContext)
                }
                .task {
                    await UnpagedAppShortcuts.updateAppShortcutParameters()
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            handlePendingIntent()
        }
    }

    private func handlePendingIntent() {
        guard UserDefaults.standard.bool(forKey: "intent.playLatestBook") else { return }
        UserDefaults.standard.removeObject(forKey: "intent.playLatestBook")
        let context = sharedModelContainer.mainContext
        var descriptor = FetchDescriptor<Audiobook>(
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let latest = try? context.fetch(descriptor).first else { return }
        Task { @MainActor in
            await audioPlayer.startPlayback(for: latest)
        }
    }
}
