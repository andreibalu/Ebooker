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
    /// Work that arrived before iCloud Drive answered this launch: book id → `QueuedUpload`.
    static let pendingUploadsKey = "iCloudAudioPendingUploads"
    /// Folders of books deleted before iCloud Drive answered, whose audio must go too.
    static let pendingDeletesKey = "iCloudAudioPendingDeletes"

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
    /// The monitor has reported at least once since connecting, so `files` is complete.
    private(set) var hasReported = false
    /// Sync is off this launch, but Settings asked to see (and maybe remove) audio left in iCloud.
    private(set) var inspectsWithoutSync = false
    var errorMessage: String?

    @ObservationIgnored private var backend: CloudAudioBackend = ICloudDriveAudioBackend()
    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var monitor: CloudAudioMonitoring?
    @ObservationIgnored private var modelContainer: ModelContainer?
    /// Files this device copied in that the monitor hasn't reported yet, by folder.
    @ObservationIgnored private var awaitingReport: [String: Set<String>] = [:]
    @ObservationIgnored private var pendingDownloads: [String: UUID] = [:]
    @ObservationIgnored private var finishingDownloads: Set<String> = []
    @ObservationIgnored private var identityObserver: NSObjectProtocol?

    private static let log = Logger(subsystem: "andreibaludev.Pageless", category: "CloudAudio")

    private init() {}

    var isActive: Bool { availability == .available }

    /// Library sync is on this launch, whether or not iCloud Drive has answered yet.
    var syncsThisLaunch: Bool { availability != .syncOff }

    /// `files` lists everything in iCloud, so "no audio" can be told apart from "not known yet".
    var knowsCloudContents: Bool { (isActive || inspectsWithoutSync) && hasReported }

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

    /// With sync off this launch nothing is stored or downloaded, but audio stored earlier still
    /// counts against the user's iCloud storage. Settings calls this to show it and offer removal.
    func inspectWithoutSync() {
        guard availability == .syncOff, !inspectsWithoutSync, IcloudSyncGate.hasUbiquityIdentity() else { return }
        inspectsWithoutSync = true
        let backend = backend
        Task {
            guard let root = await backend.audiobooksRoot() else {
                inspectsWithoutSync = false
                return
            }
            self.root = root
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
            if isActive {
                runQueuedWork()
                runMaintenance()
            }
        }
    }

    // MARK: - Upload

    /// A book was just added on this device. Before iCloud Drive answers (the first seconds after
    /// launch, or while it is off) the book waits in a queue that survives relaunch.
    func bookAdded(_ book: Audiobook) {
        guard storesNewBooks, Self.isEligible(book) else { return }
        if isActive {
            store(book)
        } else if syncsThisLaunch {
            enqueue(.add, for: book.id)
        }
    }

    /// This device replaced a book's audio (Locate…, restore on import, merge). Its old files in
    /// iCloud no longer match, so the cloud copy starts over when there is one or the setting is on.
    /// `keepsCloudCopy` is set when the audio came from another book that was in iCloud (merge).
    func bookAudioReplaced(_ book: Audiobook, keepsCloudCopy: Bool = false) {
        guard Self.isEligible(book) else { return }
        guard isActive, hasReported else {
            if syncsThisLaunch { enqueue(keepsCloudCopy ? .replaceKeepingCloudCopy : .replace, for: book.id) }
            return
        }
        if hasAnyFile(in: book.folderName) {
            upload(book, replacing: true)
        } else if storesNewBooks || keepsCloudCopy {
            upload(book, replacing: false)
        }
    }

    /// A local book merged into `merged` and its record was deleted everywhere. Its audio in iCloud
    /// goes, and the merged book is stored when the local book's audio was in iCloud.
    func bookMerged(_ merged: Audiobook, fromFolder localFolder: String) {
        guard isActive, hasReported else {
            guard syncsThisLaunch else { return }
            enqueueDelete(localFolder)
            enqueue(.mergedFrom(localFolder), for: merged.id)
            return
        }
        let localHadCloudAudio = hasAnyFile(in: localFolder)
        bookDeleted(folderName: localFolder)
        bookAudioReplaced(merged, keepsCloudCopy: localHadCloudAudio)
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
                    for (local, cloud) in pairs {
                        do {
                            try backend.copyIn(local, to: cloud)
                        } catch {
                            // Another device stored the same book at the same moment, and its copy
                            // arrived before the metadata reported it. The bytes are the same.
                            guard backend.hasSameFile(at: cloud, as: local) else { throw error }
                        }
                    }
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

    /// Deletes every book's audio from iCloud, including folders whose book is gone. Works with
    /// sync off too, after `inspectWithoutSync`.
    func removeAllCloudAudio() {
        guard isActive || inspectsWithoutSync, let root else { return }
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
    /// Before iCloud Drive has reported what it holds, the delete waits in a queue.
    func bookDeleted(folderName: String) {
        guard isActive, hasReported else {
            if syncsThisLaunch { enqueueDelete(folderName) }
            return
        }
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
        let downloads = DeviceDownloadState.shared.snapshot([book.id])
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
            try LibraryMutationTransaction.rollbackAndRethrow(error, modelContext: modelContext, transaction: transaction, downloads: downloads)
        }
    }

    // MARK: - Queue

    enum QueuedUpload: Equatable {
        case add
        case replace
        case replaceKeepingCloudCopy
        /// Merged from the book whose folder this was; keeps a cloud copy if that folder had one.
        case mergedFrom(String)

        var rawValue: String {
            switch self {
            case .add: "add"
            case .replace: "replace"
            case .replaceKeepingCloudCopy: "replaceKeep"
            case .mergedFrom(let folder): "merged:\(folder)"
            }
        }

        init?(rawValue: String) {
            switch rawValue {
            case "add": self = .add
            case "replace": self = .replace
            case "replaceKeep": self = .replaceKeepingCloudCopy
            default:
                guard rawValue.hasPrefix("merged:") else { return nil }
                self = .mergedFrom(String(rawValue.dropFirst("merged:".count)))
            }
        }
    }

    private func enqueue(_ upload: QueuedUpload, for id: UUID) {
        var queue = UserDefaults.standard.dictionary(forKey: Self.pendingUploadsKey) as? [String: String] ?? [:]
        // A replace outranks an add queued earlier for the same book.
        if let existing = queue[id.uuidString].flatMap(QueuedUpload.init(rawValue:)), upload == .add, existing != .add {
            return
        }
        queue[id.uuidString] = upload.rawValue
        UserDefaults.standard.set(queue, forKey: Self.pendingUploadsKey)
    }

    private func enqueueDelete(_ folderName: String) {
        var folders = UserDefaults.standard.stringArray(forKey: Self.pendingDeletesKey) ?? []
        guard !folders.contains(folderName) else { return }
        folders.append(folderName)
        UserDefaults.standard.set(folders, forKey: Self.pendingDeletesKey)
    }

    /// Runs at the first report once iCloud Drive is available, before maintenance, so a queued
    /// replace clears a folder before maintenance would resume it.
    private func runQueuedWork() {
        let defaults = UserDefaults.standard
        let uploads = defaults.dictionary(forKey: Self.pendingUploadsKey) as? [String: String] ?? [:]
        let deletes = defaults.stringArray(forKey: Self.pendingDeletesKey) ?? []
        guard !uploads.isEmpty || !deletes.isEmpty,
              let context = modelContainer?.mainContext,
              let books = try? context.fetch(FetchDescriptor<Audiobook>()) else { return }
        defaults.removeObject(forKey: Self.pendingUploadsKey)
        defaults.removeObject(forKey: Self.pendingDeletesKey)

        // Read before the deletes below empty those folders.
        var mergedKeeps: [UUID: Bool] = [:]
        for (key, raw) in uploads {
            if case .mergedFrom(let folder) = QueuedUpload(rawValue: raw), let id = UUID(uuidString: key) {
                mergedKeeps[id] = hasAnyFile(in: folder)
            }
        }
        let liveFolders = Set(books.map(\.folderName))
        for folder in deletes where !liveFolders.contains(folder) && hasAnyFile(in: folder) {
            removeCloudAudio(folderName: folder)
        }
        for (key, raw) in uploads {
            guard let id = UUID(uuidString: key), let upload = QueuedUpload(rawValue: raw),
                  let book = books.first(where: { $0.id == id }) else { continue }
            switch upload {
            case .add:
                if storesNewBooks { store(book) }
            case .replace:
                bookAudioReplaced(book)
            case .replaceKeepingCloudCopy:
                bookAudioReplaced(book, keepsCloudCopy: true)
            case .mergedFrom:
                bookAudioReplaced(book, keepsCloudCopy: mergedKeeps[id] ?? false)
            }
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
