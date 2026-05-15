//
//  AppDelegate.swift
//  Pageless
//

import CarPlay
import OSLog
import SwiftData
import UIKit

private let carPlayLog = Logger(subsystem: "andreibaludev.Pageless", category: "CarPlay")

/// Supplies the CarPlay scene configuration alongside SwiftUI `WindowGroup`.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    static weak var shared: AppDelegate?

    let modelContainer: ModelContainer
    let audioPlayer: AudioPlayerManager
    let freeBookDownloader: FreeBookDownloadService
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
        self.freeBookDownloader = FreeBookDownloadService()
        super.init()
        AppDelegate.shared = self
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
        carPlayLog.info("configurationForConnecting role=\(connectingSceneSession.role.rawValue, privacy: .public)")
        if connectingSceneSession.role == .carTemplateApplication {
            carPlayLog.info("returning CarPlay scene configuration")
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
