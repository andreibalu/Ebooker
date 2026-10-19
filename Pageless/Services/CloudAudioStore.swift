//
//  CloudAudioStore.swift
//  Pageless
//

import Foundation
import OSLog
import SwiftData

/// Owns "audio in iCloud": copies of own (imported) books' audio files in the app's iCloud Drive
/// container, so another device or a reinstall can download the whole book. Free LibriVox and
/// Audiobookshelf books never go here; they download again from their source.
///
/// Works only while library sync is on this launch, because the synced record is what tells
/// another device the book exists. The record and its audio share `Audiobook.folderName`:
/// `<container>/Audiobooks/<folderName>/<storedFileName>` mirrors local storage.
@MainActor
@Observable
final class CloudAudioStore {
    static let shared = CloudAudioStore()

    /// Per-device choice: store each new book's audio in iCloud as it is added.
    static let preferenceKey = "iCloudAudioEnabled"

    enum Availability: Equatable {
        /// Library sync is off this launch.
        case syncOff
        case checking
        case available
        /// iCloud Drive is off for this account or for Unpaged.
        case driveUnavailable
    }

    private(set) var availability: Availability = .syncOff
    private(set) var files: [String: CloudAudioFileStatus] = [:]
    private(set) var downloadProgress: [String: Double] = [:]
    private(set) var copyingFolders: Set<String> = []
    var errorMessage: String?

    @ObservationIgnored private var backend: CloudAudioBackend = ICloudDriveAudioBackend()
    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var monitor: CloudAudioMonitoring?
    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var hasReported = false
    /// Files this device copied in that the monitor hasn't reported yet, by folder.
    @ObservationIgnored private var awaitingReport: [String: Set<String>] = [:]
    @ObservationIgnored private var pendingDownloads: [String: UUID] = [:]
    @ObservationIgnored private var finishingDownloads: Set<String> = []
    @ObservationIgnored private var identityObserver: NSObjectProtocol?

    private static let log = Logger(subsystem: "andreibaludev.Pageless", category: "CloudAudio")

    private init() {}

    var isActive: Bool { availability == .available }

    var storesNewBooks: Bool { UserDefaults.standard.bool(forKey: Self.preferenceKey) }

    func start(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        #if DEBUG
        if E2EFixtures.enabled { backend = E2EFixtures.cloudAudioBackend() }
        #endif
        guard IcloudSyncGate.isEnabled() else {
            availability = .syncOff
            return
        }
        connect()
        identityObserver = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.connect() }
        }
    }

    private func connect() {
        monitor?.stop()
        monitor = nil
        files = [:]
        hasReported = false
        availability = .checking
        let backend = backend
        Task {
            guard let root = await backend.audiobooksRoot() else {
                availability = .driveUnavailable
                return
            }
            self.root = root
            availability = .available
            monitor = backend.startMonitoring(root: root) { [weak self] statuses in
                self?.apply(statuses)
            }
        }
    }

    // MARK: - State

    static func isEligible(_ book: Audiobook) -> Bool {
        !book.isFreeBook && !book.isAudiobookshelfBook && !book.tracks.isEmpty
    }

    func state(for book: Audiobook) -> CloudAudioState {
        guard isActive, Self.isEligible(book) else { return .none }
        return .derive(
            folderName: book.folderName,
            trackFileNames: book.sortedTracks.map(\.storedFileName),
            files: files,
            isCopying: isCopying(book.folderName)
        )
    }

    /// This device is still copying the book's files in. Files not yet copied exist only locally.
    func isCopyingIn(_ book: Audiobook) -> Bool {
        copyingFolders.contains(book.folderName)
    }

    func isDownloading(_ book: Audiobook) -> Bool {
        downloadProgress[book.folderName] != nil
    }

    /// Books with at least one file in iCloud, and their total size.
    var usage: (books: Int, bytes: Int64) {
        var folders = Set<String>()
        var bytes: Int64 = 0
        for (key, status) in files {
            if let folder = key.split(separator: "/").first { folders.insert(String(folder)) }
            bytes += status.size
        }
        return (folders.count, bytes)
    }

    private func hasAnyFile(in folderName: String) -> Bool {
        files.keys.contains { $0.hasPrefix("\(folderName)/") }
    }

    private func isCopying(_ folderName: String) -> Bool {
        copyingFolders.contains(folderName) || !(awaitingReport[folderName]?.isEmpty ?? true)
    }

    private func apply(_ statuses: [String: CloudAudioFileStatus]) {
        files = statuses
        for (folder, names) in awaitingReport {
            let remaining = names.filter { statuses[CloudAudioPlan.key(folder, $0)] == nil }
            awaitingReport[folder] = remaining.isEmpty ? nil : remaining
        }
        advanceDownloads()
        if !hasReported {
            hasReported = true
            runMaintenance()
        }
    }

    // MARK: - Upload

    /// A book was just added on this device.
    func bookAdded(_ book: Audiobook) {
        guard storesNewBooks else { return }
        store(book)
    }

    /// This device replaced a book's audio (Locate…, restore on import, merge). Its old files in
    /// iCloud no longer match, so the cloud copy starts over when there is one or the setting is on.
    /// `keepsCloudCopy` is set when the audio came from another book that was in iCloud (merge).
    func bookAudioReplaced(_ book: Audiobook, keepsCloudCopy: Bool = false) {
        guard isActive, Self.isEligible(book) else { return }
        if hasAnyFile(in: book.folderName) {
            upload(book, replacing: true)
        } else if storesNewBooks || keepsCloudCopy {
            upload(book, replacing: false)
        }
    }

    /// Copies every track file iCloud lacks. Safe to call again; never overwrites.
    func store(_ book: Audiobook) {
        upload(book, replacing: false)
    }

    /// Stores every own book downloaded on this device.
    func storeAll(_ books: [Audiobook]) {
        for book in books where book.isDownloaded {
            store(book)
        }
    }

    private func upload(_ book: Audiobook, replacing: Bool) {
        guard isActive, let root, Self.isEligible(book), book.isDownloaded else { return }
        let folder = book.folderName
        guard !copyingFolders.contains(folder),
              let localFolder = try? LibraryMutationTransaction.folderURL(
                for: folder,
                rootURL: LibraryMutationTransaction.defaultAudiobooksRoot()
              ),
              let cloudFolder = try? LibraryMutationTransaction.folderURL(for: folder, rootURL: root)
        else { return }
        let names = book.sortedTracks.map(\.storedFileName)
        let toCopy = replacing
            ? names
            : CloudAudioPlan.filesToCopy(folderName: folder, trackFileNames: names, files: files)
        guard let pairs = try? toCopy.map({ name in
            (try LibraryMutationTransaction.fileURL(for: name, in: localFolder, rootURL: LibraryMutationTransaction.defaultAudiobooksRoot()),
             try LibraryMutationTransaction.fileURL(for: name, in: cloudFolder, rootURL: root))
        }), !pairs.isEmpty,
              // Launch maintenance can run before orphan detection catches a missing folder.
              pairs.allSatisfy({ FileManager.default.fileExists(atPath: $0.0.path(percentEncoded: false)) })
        else { return }

        copyingFolders.insert(folder)
        if replacing { files = files.filter { !$0.key.hasPrefix("\(folder)/") } }
        let backend = backend
        Task {
            let failure: String? = await Task.detached(priority: .utility) {
                do {
                    if replacing { try backend.remove(cloudFolder) }
                    for (local, cloud) in pairs { try backend.copyIn(local, to: cloud) }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            copyingFolders.remove(folder)
            if let failure {
                Self.log.error("Copying audio to iCloud failed: \(failure, privacy: .public)")
                errorMessage = "Unpaged couldn't copy this book's audio to iCloud. \(failure)"
            } else {
                awaitingReport[folder, default: []].formUnion(toCopy)
                // Stop treating the folder as copying if the report never arrives.
                Task {
                    try? await Task.sleep(for: .seconds(30))
                    awaitingReport[folder] = nil
                }
            }
            monitor?.refresh()
        }
    }

    // MARK: - Remove

    /// Deletes a book's audio from iCloud on every device. The book and any local copy stay.
    func removeCloudAudio(folderName: String) {
        guard isActive, let root,
              let cloudFolder = try? LibraryMutationTransaction.folderURL(for: folderName, rootURL: root)
        else { return }
        files = files.filter { !$0.key.hasPrefix("\(folderName)/") }
        awaitingReport[folderName] = nil
        let backend = backend
        Task {
            let failure: String? = await Task.detached(priority: .utility) {
                do {
                    try backend.remove(cloudFolder)
                    return nil
                } catch CocoaError.fileNoSuchFile {
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let failure { errorMessage = "Unpaged couldn't remove this audio from iCloud. \(failure)" }
            monitor?.refresh()
        }
    }

    /// Deletes every book's audio from iCloud, including folders whose book is gone.
    func removeAllCloudAudio() {
        guard isActive, let root else { return }
        files = [:]
        awaitingReport = [:]
        let backend = backend
        Task {
            let failure: String? = await Task.detached(priority: .utility) {
                do {
                    try backend.remove(root)
                    return nil
                } catch CocoaError.fileNoSuchFile {
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let failure { errorMessage = "Unpaged couldn't remove audio from iCloud. \(failure)" }
            monitor?.refresh()
        }
    }

    /// A synced record was permanently deleted on this device, which deletes it on every device.
    /// Its audio goes with it. With sync off the record still exists in iCloud, so nothing is touched.
    func bookDeleted(folderName: String) {
        guard hasAnyFile(in: folderName) else { return }
        removeCloudAudio(folderName: folderName)
    }

    /// "Remove from this iPhone" kept the book and its cloud audio. Drop this device's copy of the
    /// cloud files too, or the clone keeps the space the removal meant to free. Files still
    /// uploading keep their data until iCloud has them; maintenance evicts them on a later launch.
    func evictLocalCopies(folderName: String) {
        guard isActive, let root else { return }
        let urls = files.compactMap { key, status -> URL? in
            guard key.hasPrefix("\(folderName)/"), status.isUploaded, status.isDownloaded else { return nil }
            return root.appendingPathComponent(key, isDirectory: false)
        }
        guard !urls.isEmpty else { return }
        let backend = backend
        Task.detached(priority: .utility) {
            for url in urls { try? backend.evict(url) }
        }
    }

    // MARK: - Download

    /// Downloads an "In iCloud only" book's audio, then moves it into local storage.
    func download(_ book: Audiobook) {
        guard isActive, let root, book.isCloudOnlyOrphan, state(for: book) == .stored,
              downloadProgress[book.folderName] == nil,
              let cloudFolder = try? LibraryMutationTransaction.folderURL(for: book.folderName, rootURL: root),
              let urls = try? book.sortedTracks.map({
                  try LibraryMutationTransaction.fileURL(for: $0.storedFileName, in: cloudFolder, rootURL: root)
              })
        else { return }
        let folder = book.folderName
        downloadProgress[folder] = 0
        pendingDownloads[folder] = book.id
        let backend = backend
        Task {
            let failure: String? = await Task.detached(priority: .utility) {
                do {
                    for url in urls { try backend.startDownloading(url) }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let failure {
                downloadProgress[folder] = nil
                pendingDownloads[folder] = nil
                errorMessage = "Unpaged couldn't download this book from iCloud. \(failure)"
            }
            advanceDownloads()
        }
    }

    private func advanceDownloads() {
        guard let context = modelContainer?.mainContext else { return }
        for (folder, id) in pendingDownloads where !finishingDownloads.contains(folder) {
            var descriptor = FetchDescriptor<Audiobook>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let book = try? context.fetch(descriptor).first else {
                pendingDownloads[folder] = nil
                downloadProgress[folder] = nil
                continue
            }
            let statuses = book.sortedTracks.map { files[CloudAudioPlan.key(folder, $0.storedFileName)] }
            guard statuses.allSatisfy({ $0 != nil }) else {
                // The audio left iCloud mid-download (removed from another device).
                pendingDownloads[folder] = nil
                downloadProgress[folder] = nil
                errorMessage = "This book's audio is no longer in iCloud."
                continue
            }
            let present = statuses.compactMap { $0 }
            let total = present.reduce(0.0) { $0 + Double(max($1.size, 1)) }
            let done = present.reduce(0.0) { $0 + Double(max($1.size, 1)) * ($1.isDownloaded ? 1 : $1.downloadFraction) }
            downloadProgress[folder] = total > 0 ? done / total : 0
            if present.allSatisfy(\.isDownloaded) {
                finishDownload(book)
            }
        }
    }

    private func finishDownload(_ book: Audiobook) {
        guard let root, let context = modelContainer?.mainContext else { return }
        let folder = book.folderName
        finishingDownloads.insert(folder)
        let names = book.sortedTracks.map(\.storedFileName)
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudAudio-\(UUID().uuidString)", isDirectory: true)
        guard let cloudFolder = try? LibraryMutationTransaction.folderURL(for: folder, rootURL: root),
              let pairs = try? names.map({ name in
                  (try LibraryMutationTransaction.fileURL(for: name, in: cloudFolder, rootURL: root),
                   staging.appendingPathComponent(name, isDirectory: false))
              })
        else {
            finishingDownloads.remove(folder)
            return
        }
        let backend = backend
        Task {
            defer {
                finishingDownloads.remove(folder)
                pendingDownloads[folder] = nil
                downloadProgress[folder] = nil
                try? FileManager.default.removeItem(at: staging)
            }
            let copyFailure: String? = await Task.detached(priority: .utility) {
                do {
                    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                    for (cloud, local) in pairs { try backend.copyOut(cloud, to: local) }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let copyFailure {
                errorMessage = "Unpaged couldn't download this book from iCloud. \(copyFailure)"
                return
            }
            guard !book.isDeleted, book.isCloudOnlyOrphan else { return }
            do {
                try Self.adoptDownloadedFiles(names: names, from: staging, into: book, modelContext: context)
                ContinueListeningSnapshotWriter.shared.refresh(context: context)
                Self.log.info("Downloaded a book's audio from iCloud tracks=\(names.count, privacy: .public)")
            } catch {
                errorMessage = "Unpaged couldn't save this book's audio. \(error.localizedDescription)"
            }
        }
    }

    /// The files are the book's own tracks under their stored names, so the track records already
    /// describe them; only `isDownloaded` changes.
    private static func adoptDownloadedFiles(
        names: [String],
        from staging: URL,
        into book: Audiobook,
        modelContext: ModelContext
    ) throws {
        let transaction = try LibraryMutationTransaction()
        do {
            for name in names {
                _ = try transaction.stageCopy(from: staging.appendingPathComponent(name, isDirectory: false), named: name)
            }
            let folderURL = try LibraryMutationTransaction.folderURL(for: book.folderName, rootURL: transaction.rootURL)
            try transaction.backupExistingFolder(at: folderURL)
            try transaction.promoteStaging(to: folderURL)
            book.isDownloaded = true
            try modelContext.save()
            do {
                try transaction.commit()
            } catch {
                throw LibraryMutationError.modelCommittedButTransactionMarkerFailed(error)
            }
        } catch {
            if case LibraryMutationError.modelCommittedButTransactionMarkerFailed = error { throw error }
            try LibraryMutationTransaction.rollbackAndRethrow(error, modelContext: modelContext, transaction: transaction)
        }
    }

    // MARK: - Maintenance

    /// After the first report each launch: finish uploads an earlier launch left half done, and
    /// drop local copies of cloud files for books this device no longer keeps.
    private func runMaintenance() {
        guard let context = modelContainer?.mainContext,
              let books = try? context.fetch(FetchDescriptor<Audiobook>()) else { return }
        for book in books where Self.isEligible(book) && hasAnyFile(in: book.folderName) {
            if book.isDownloaded {
                store(book)
            } else if book.isCloudOnlyOrphan {
                evictLocalCopies(folderName: book.folderName)
            }
        }
    }
}
