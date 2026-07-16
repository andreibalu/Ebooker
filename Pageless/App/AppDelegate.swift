//
//  AppDelegate.swift
//  Pageless
//

import CarPlay
import CoreData
import OSLog
import SwiftData
import UIKit

private let carPlayLog = Logger(subsystem: "andreibaludev.Pageless", category: "CarPlay")

@MainActor
final class BackgroundSessionCompletionRegistry {
    private var handlers: [String: [() -> Void]] = [:]
    private var pendingReleases: Set<String> = []
    private var restorationReady: Set<String> = []
    private var consumed: Set<String> = []
    private var activeCycles: Set<String> = []

    func beginCycle(for identifier: String) {
        guard !activeCycles.contains(identifier) else { return }
        activeCycles.insert(identifier)
        restorationReady.remove(identifier)
        consumed.remove(identifier)
    }

    private func consumeHandlers(for identifier: String) -> (() -> Void)? {
        guard let handlers = handlers.removeValue(forKey: identifier), !handlers.isEmpty else {
            return nil
        }
        consumed.insert(identifier)
        activeCycles.remove(identifier)
        return {
            handlers.forEach { $0() }
        }
    }

    @discardableResult
    func store(_ handler: @escaping () -> Void, for identifier: String) -> (() -> Void)? {
        guard !consumed.contains(identifier) else { return nil }
        handlers[identifier, default: []].append(handler)
        if pendingReleases.contains(identifier), restorationReady.contains(identifier) {
            pendingReleases.remove(identifier)
            return consumeHandlers(for: identifier)
        }
        return nil
    }

    func take(for identifier: String) -> (() -> Void)? {
        consumeHandlers(for: identifier)
    }

    func requestCompletion(for identifier: String) -> (() -> Void)? {
        guard !consumed.contains(identifier) else { return nil }
        if !handlers[identifier, default: []].isEmpty {
            guard restorationReady.contains(identifier) else {
                pendingReleases.insert(identifier)
                return nil
            }
            pendingReleases.remove(identifier)
            return consumeHandlers(for: identifier)
        }
        pendingReleases.insert(identifier)
        return nil
    }

    @discardableResult
    func markRestorationReady(for identifier: String) -> (() -> Void)? {
        restorationReady.insert(identifier)
        guard pendingReleases.remove(identifier) != nil else { return nil }
        return consumeHandlers(for: identifier)
    }

    @discardableResult
    func markRestorationFailed(for identifier: String) -> (() -> Void)? {
        // Durable fail-closed outcome. Preserve release handshake.
        restorationReady.insert(identifier)
        guard pendingReleases.remove(identifier) != nil else { return nil }
        return consumeHandlers(for: identifier)
    }
}

/// Supplies the CarPlay scene configuration alongside SwiftUI `WindowGroup`.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    static weak var shared: AppDelegate?

    let modelContainer: ModelContainer
    let audioPlayer: AudioPlayerManager
    let freeBookDownloader: FreeBookDownloadService
    let libriVoxDownloadCoordinator: LibriVoxBackgroundDownloadCoordinator
    let libriVoxDownloadRuntime: LibriVoxDownloadRuntime
    private let backgroundSessionCompletionRegistry = BackgroundSessionCompletionRegistry()
    private var cloudKitImportObserver: NSObjectProtocol?

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
        self.libriVoxDownloadCoordinator = LibriVoxBackgroundDownloadCoordinator(
            modelContext: modelContainer.mainContext
        )
        self.libriVoxDownloadRuntime = LibriVoxDownloadRuntime(
            coordinator: libriVoxDownloadCoordinator,
            activityController: DownloadLiveActivityController(),
            isAppActive: { UIApplication.shared.applicationState == .active }
        )
        super.init()
        AppDelegate.shared = self

        FingerprintBackfillService.runIfNeeded(modelContainer: modelContainer)
        OrphanDetectionService.runIfNeeded(modelContainer: modelContainer)

        // Re-run orphan detection whenever CloudKit finishes an import. Books synced from
        // iCloud arrive with isDownloaded = true; we need to flip that flag for any book
        // whose audio files don't exist locally, or they'll appear in the main library.
        if syncEnabled {
            cloudKitImportObserver = NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event,
                      event.type == .import,
                      event.endDate != nil,
                      event.succeeded
                else { return }
                OrphanDetectionService.runIfNeeded(modelContainer: self.modelContainer)
            }
        }

    }

    nonisolated func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            backgroundSessionCompletionRegistry.beginCycle(for: identifier)
            let handlerReadyBeforeConfiguration = backgroundSessionCompletionRegistry.store(
                completionHandler,
                for: identifier
            )
            var restorationSucceeded = true
            if identifier == FreeBookDownloadService.backgroundSessionIdentifier {
                restorationSucceeded = await freeBookDownloader.restoreBackgroundSession(
                    modelContext: modelContainer.mainContext
                )
            } else if identifier == LibriVoxBackgroundDownloadCoordinator.sessionIdentifier {
                restorationSucceeded = await libriVoxDownloadCoordinator.restoreBackgroundSession()
            }
            if restorationSucceeded {
                UserDefaults.standard.removeObject(
                    forKey: "BackgroundSessionRecoveryError.\(identifier)"
                )
                (handlerReadyBeforeConfiguration
                    ?? backgroundSessionCompletionRegistry.markRestorationReady(for: identifier))?()
            } else {
                UserDefaults.standard.set(
                    "Background restoration halted; retry required.",
                    forKey: "BackgroundSessionRecoveryError.\(identifier)"
                )
                backgroundSessionCompletionRegistry.markRestorationFailed(for: identifier)?()
            }
        }
    }

    func takeBackgroundSessionCompletionHandler(for identifier: String) -> (() -> Void)? {
        backgroundSessionCompletionRegistry.take(for: identifier)
    }

    func requestBackgroundSessionCompletionHandler(for identifier: String) -> (() -> Void)? {
        backgroundSessionCompletionRegistry.requestCompletion(for: identifier)
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
