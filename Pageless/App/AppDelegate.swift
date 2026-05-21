//
//  AppDelegate.swift
//  Pageless
//

import CarPlay
import OSLog
import RevenueCat
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
        // Synced models live in the default store and optionally back onto the user's private
        // CloudKit database. The LibriVox catalog cache (20k rows) is in a separate store and
        // never syncs — it refreshes from the LibriVox API on its own cadence.
        let syncedSchema = Schema([
            Audiobook.self,
            AudioTrack.self,
            Moment.self,
            ReadingSession.self,
        ])
        let localSchema = Schema([
            LibriVoxBook.self,
        ])

        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let syncedStoreURL = supportURL.appendingPathComponent("default.store")
        let localStoreURL = supportURL.appendingPathComponent("librivox-catalog.store")

        let syncEnabled = IcloudSyncGate.isEnabled()
        let syncedConfiguration = ModelConfiguration(
            "synced",
            schema: syncedSchema,
            url: syncedStoreURL,
            cloudKitDatabase: syncEnabled ? .private(IcloudSyncGate.containerIdentifier) : .none
        )
        let localConfiguration = ModelConfiguration(
            "local",
            schema: localSchema,
            url: localStoreURL,
            cloudKitDatabase: .none
        )

        do {
            self.modelContainer = try ModelContainer(
                for: Audiobook.self,
                AudioTrack.self,
                Moment.self,
                ReadingSession.self,
                LibriVoxBook.self,
                configurations: syncedConfiguration, localConfiguration
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        self.audioPlayer = AudioPlayerManager()
        self.freeBookDownloader = FreeBookDownloadService()
        super.init()
        AppDelegate.shared = self

        FingerprintBackfillService.runIfNeeded(modelContainer: modelContainer)
        OrphanDetectionService.runIfNeeded(modelContainer: modelContainer)

        #if DEBUG
        Purchases.logLevel = .info
        let rcAPIKey = "test_qeiEKewUdXbJfItZAOSWMKUiCcz"
        #else
        let rcAPIKey = "appl_fLJZEZIjoyasIHSFeJyYlqHmfzx"
        #endif
        Purchases.configure(
            with: Configuration.Builder(withAPIKey: rcAPIKey)
                .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                .build()
        )
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
