//
//  PagelessApp.swift
//  Pageless
//

import AVFoundation
import SwiftData
import SwiftUI

@main
struct PagelessApp: App {
    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var aiEntitlementStore = AIEntitlementStore()

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
        }
        .modelContainer(sharedModelContainer)
    }
}
