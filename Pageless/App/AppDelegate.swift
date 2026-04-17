//
//  AppDelegate.swift
//  Pageless
//

import CarPlay
import SwiftData
import UIKit

/// Supplies the CarPlay scene configuration alongside SwiftUI `WindowGroup`.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let modelContainer: ModelContainer
    let audioPlayer: AudioPlayerManager
    var backgroundSessionCompletionHandler: (() -> Void)?

    override init() {
        let schema = Schema([
            Audiobook.self,
            AudioTrack.self,
            Moment.self,
            LibriVoxBook.self,
        ])

        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let storeURL = supportURL.appendingPathComponent("default.store")

        let modelConfiguration = ModelConfiguration(url: storeURL)

        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        self.audioPlayer = AudioPlayerManager()
        super.init()
    }

    nonisolated func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            backgroundSessionCompletionHandler = completionHandler
        }
    }

    nonisolated func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let configuration = UISceneConfiguration(
                name: "CarPlay",
                sessionRole: connectingSceneSession.role
            )
            configuration.delegateClass = CarPlaySceneDelegate.self
            return configuration
        }
        return UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }
}
