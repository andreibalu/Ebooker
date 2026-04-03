//
//  PagelessApp.swift
//  Pageless
//

import AVFoundation
import SwiftData
import SwiftUI

@main
struct PagelessApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var aiEntitlementStore = AIEntitlementStore()
    @State private var onboardingManager = OnboardingManager()
    @State private var deepLinkBookID: String?

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
                .onAppear {
                    appDelegate.modelContainer = sharedModelContainer
                    appDelegate.audioPlayer = audioPlayer
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "pageless" else { return }
        switch url.host {
        case "nowplaying":
            // App opens to current playback — no extra navigation needed
            break
        case "book":
            let bookID = url.pathComponents.dropFirst().first
            deepLinkBookID = bookID
        case "library":
            break
        default:
            break
        }
    }
}
