//
//  ICloudDriveAudioBackend.swift
//  Pageless
//

import Foundation

/// Audio in the app's iCloud Drive ubiquity container, `<container>/Audiobooks/<folderName>/`.
/// The folder sits outside `Documents`, so the Files app doesn't show it. The system's iCloud Drive
/// daemon uploads, downloads and retries in the background, following the user's iCloud Drive
/// cellular setting.
nonisolated struct ICloudDriveAudioBackend: CloudAudioBackend {
    func audiobooksRoot() async -> URL? {
        // The first lookup can block while the system sets up the container.
        await Task.detached(priority: .utility) {
            FileManager.default
                .url(forUbiquityContainerIdentifier: IcloudSyncGate.containerIdentifier)?
                .appendingPathComponent("Audiobooks", isDirectory: true)
        }.value
    }

    func copyIn(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try coordinate(writing: destination.deletingLastPathComponent(), options: []) { folder in
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        // Clone into tmp on the same volume, then hand the clone to iCloud. APFS clones share
        // blocks with the original, so the cloud copy costs no extra local storage.
        let staged = fileManager.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(destination.lastPathComponent)")
        try fileManager.copyItem(at: source, to: staged)
        do {
            try fileManager.setUbiquitous(true, itemAt: staged, destinationURL: destination)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
    }

    /// Same name in the same book's folder means the same track of the same record; the size
    /// confirms it when the system knows it. A legacy `.name.icloud` placeholder has no readable
    /// size, so its presence is enough.
    func hasSameFile(at destination: URL, as source: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .totalFileSizeKey]
        guard let sourceSize = (try? source.resourceValues(forKeys: keys))?.fileSize else { return false }
        var matches = false
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: destination,
            options: .immediatelyAvailableMetadataOnly,
            error: &coordinationError
        ) { url in
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                let values = try? url.resourceValues(forKeys: keys)
                if let size = values?.fileSize ?? values?.totalFileSize {
                    matches = size == sourceSize
                } else {
                    matches = true
                }
            } else {
                let placeholder = url.deletingLastPathComponent()
                    .appendingPathComponent(".\(url.lastPathComponent).icloud")
                matches = FileManager.default.fileExists(atPath: placeholder.path(percentEncoded: false))
            }
        }
        return coordinationError == nil && matches
    }

    func remove(_ url: URL) throws {
        try coordinate(writing: url, options: .forDeleting) { url in
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                // A file this device never downloaded may exist only as a `.name.icloud` placeholder.
                let placeholder = url.deletingLastPathComponent()
                    .appendingPathComponent(".\(url.lastPathComponent).icloud")
                if FileManager.default.fileExists(atPath: placeholder.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: placeholder)
                }
            }
        }
    }

    func startDownloading(_ url: URL) throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    func evict(_ url: URL) throws {
        try FileManager.default.evictUbiquitousItem(at: url)
    }

    func copyOut(_ source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: source,
            options: .withoutChanges,
            error: &coordinationError
        ) { url in
            do { try FileManager.default.copyItem(at: url, to: destination) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
    }

    @MainActor
    func startMonitoring(
        root: URL,
        onChange: @escaping @MainActor ([String: CloudAudioFileStatus]) -> Void
    ) -> CloudAudioMonitoring {
        ICloudDriveAudioMonitor(onChange: onChange)
    }

    private func coordinate(
        writing url: URL,
        options: NSFileCoordinator.WritingOptions,
        _ body: (URL) throws -> Void
    ) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: options,
            error: &coordinationError
        ) { url in
            do { try body(url) } catch { bodyError = error }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }
}

/// Reports every file under `Audiobooks/<folder>/` in the ubiquity container through a live
/// `NSMetadataQuery`. Files another device uploaded appear here before any data downloads.
@MainActor
final class ICloudDriveAudioMonitor: CloudAudioMonitoring {
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private let onChange: @MainActor ([String: CloudAudioFileStatus]) -> Void

    init(onChange: @escaping @MainActor ([String: CloudAudioFileStatus]) -> Void) {
        self.onChange = onChange
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*")
        query.notificationBatchingInterval = 1
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name,
                object: query,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.publish() }
            })
        }
        query.start()
    }

    func refresh() {
        // The query observes the container itself; changes this app makes arrive as updates.
    }

    func stop() {
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func publish() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var statuses: [String: CloudAudioFileStatus] = [:]
        var conflicted: [URL] = []
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let parts = url.pathComponents
            guard parts.count >= 3, parts[parts.count - 3] == "Audiobooks" else { continue }

            let downloading = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let isDownloaded = downloading == NSMetadataUbiquitousItemDownloadingStatusCurrent
                || downloading == NSMetadataUbiquitousItemDownloadingStatusDownloaded
            let percentUploaded = (item.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double) ?? 0
            let percentDownloaded = (item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double) ?? 0
            statuses[CloudAudioPlan.key(parts[parts.count - 2], parts[parts.count - 1])] = CloudAudioFileStatus(
                size: (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value ?? 0,
                isUploaded: (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool) ?? false,
                uploadFraction: percentUploaded / 100,
                isDownloaded: isDownloaded,
                downloadFraction: isDownloaded ? 1 : percentDownloaded / 100,
                uploadError: Self.uploadError(item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError)
            )
            if (item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool) == true {
                conflicted.append(url)
            }
        }
        onChange(statuses)
        if !conflicted.isEmpty {
            Task.detached(priority: .utility) { Self.resolveConflicts(conflicted) }
        }
    }

    /// Offline and server hiccups only delay an upload; iCloud retries those on its own.
    private static func uploadError(_ error: NSError?) -> CloudAudioUploadError? {
        guard let error else { return nil }
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case CocoaError.ubiquitousFileNotUploadedDueToQuota.rawValue: return .quotaExceeded
            case CocoaError.ubiquitousFileUbiquityServerNotAvailable.rawValue: return nil
            default: return .other
            }
        }
        return error.domain == NSURLErrorDomain ? nil : .other
    }

    /// Two devices that stored the same book upload the same bytes under the same name, so the
    /// current version is as good as any other.
    nonisolated private static func resolveConflicts(_ urls: [URL]) {
        for url in urls {
            var coordinationError: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(
                writingItemAt: url,
                options: .forReplacing,
                error: &coordinationError
            ) { url in
                try? NSFileVersion.removeOtherVersionsOfItem(at: url)
                for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
                    version.isResolved = true
                }
            }
        }
    }
}
