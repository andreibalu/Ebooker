//
//  LibriVoxBookDetailViewModel.swift
//  Pageless
//

import Foundation
import Observation
import SwiftData

@Observable
final class LibriVoxBookDetailViewModel {
    enum DownloadState {
        case idle
        case fetchingTracks
        case downloading(completed: Int, total: Int)
        case complete(Audiobook)
        case failed(String)

        var isActive: Bool {
            switch self {
            case .fetchingTracks, .downloading: return true
            default: return false
            }
        }

        var progress: Double? {
            if case .downloading(let c, let t) = self, t > 0 {
                return Double(c) / Double(t)
            }
            return nil
        }
    }

    var downloadState: DownloadState = .idle

    enum AddToLibraryState {
        case idle
        case loading
        case complete(Audiobook)
        case failed(String)
    }

    var addToLibraryState: AddToLibraryState = .idle

    /// Set when the user taps Add/Download for a free book that has an archived iCloud backup
    /// (matched by catalog id). The view shows a confirmation offering "Import from iCloud" (restore
    /// the backup's progress/moments) vs "Add as New". Mirrors own books' RestoreMatchSheet.
    struct PendingFreeRestore {
        let backup: Audiobook
        let book: LibriVoxBook
        let isDownload: Bool
    }

    var pendingRestore: PendingFreeRestore?

    private var downloadTask: Task<Void, Never>?
    private weak var tracker: BrowseLibriVoxViewModel?
    private var trackedBookId: String?

    /// True when already added to library (via streaming or download).
    var isAlreadyInLibrary: Bool {
        switch downloadState {
        case .complete: return true
        default: break
        }
        switch addToLibraryState {
        case .complete: return true
        default: return false
        }
    }

    func startDownload(book: LibriVoxBook, modelContext: ModelContext, tracker: BrowseLibriVoxViewModel? = nil) {
        guard !downloadState.isActive else { return }
        self.tracker = tracker
        self.trackedBookId = book.id
        // Auto-match against an archived iCloud backup by catalog id; if found, ask before adding.
        if IcloudSyncGate.isEnabled(),
           let backup = OrphanRestoreService.fetchFreeBackup(catalogId: book.id, modelContext: modelContext) {
            pendingRestore = PendingFreeRestore(backup: backup, book: book, isDownload: true)
            return
        }
        downloadTask = Task { [weak self] in
            await self?.performDownload(book: book, modelContext: modelContext)
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadState = .idle
        if let bookId = trackedBookId {
            tracker?.cancelOrFailDownload(bookId: bookId)
        }
    }

    func addToLibrary(book: LibriVoxBook, modelContext: ModelContext) {
        guard case .idle = addToLibraryState else { return }
        // Auto-match against an archived iCloud backup by catalog id; if found, ask before adding.
        if IcloudSyncGate.isEnabled(),
           let backup = OrphanRestoreService.fetchFreeBackup(catalogId: book.id, modelContext: modelContext) {
            pendingRestore = PendingFreeRestore(backup: backup, book: book, isDownload: false)
            return
        }
        Task { [weak self] in
            await self?.performAddToLibrary(book: book, modelContext: modelContext)
        }
    }

    /// User chose "Import from iCloud" on the restore prompt: bring the archived backup back with its
    /// synced progress/moments. Streaming reuses the record as-is; downloading re-fetches files into it.
    func confirmRestore(modelContext: ModelContext) {
        guard let pending = pendingRestore else { return }
        pendingRestore = nil
        let backup = pending.backup
        backup.isArchived = false
        if pending.isDownload {
            try? modelContext.save()
            self.trackedBookId = pending.book.id
            downloadTask = Task { [weak self] in
                await self?.performRestoreDownload(backup: backup, book: pending.book, modelContext: modelContext)
            }
        } else {
            backup.isDownloaded = false
            try? modelContext.save()
            addToLibraryState = .complete(backup)
        }
    }

    /// User chose "Add as New" on the restore prompt: ignore the backup and create a fresh copy. The
    /// detail view's iCloud button still lets them match into the backup later.
    func declineRestoreAddAsNew(modelContext: ModelContext) {
        guard let pending = pendingRestore else { return }
        pendingRestore = nil
        if pending.isDownload {
            downloadTask = Task { [weak self] in
                await self?.performDownload(book: pending.book, modelContext: modelContext)
            }
        } else {
            Task { [weak self] in
                await self?.performAddToLibrary(book: pending.book, modelContext: modelContext)
            }
        }
    }

    @MainActor
    private func performAddToLibrary(book: LibriVoxBook, modelContext: ModelContext) async {
        addToLibraryState = .loading
        do {
            let cached: [CachedLibriVoxTrack]
            if let existing = book.cachedTracks {
                cached = existing
            } else {
                guard NetworkMonitor.shared.isConnected else {
                    addToLibraryState = .failed("Connect to the internet to load track info for this book.")
                    return
                }
                let apiTracks = try await LibriVoxAPIClient.fetchTracks(projectID: book.id)
                guard !apiTracks.isEmpty else {
                    addToLibraryState = .failed("This book has no available tracks.")
                    return
                }
                cached = apiTracks.enumerated().map { i, t in
                    CachedLibriVoxTrack(title: t.title, listenURL: t.listenURL, durationSeconds: t.durationSeconds, orderIndex: i)
                }
                book.cachedTracks = cached
                try? modelContext.save()
            }

            let audiobook = try await StreamingLibraryService.addToLibrary(
                book: book, tracks: cached, modelContext: modelContext
            )
            addToLibraryState = .complete(audiobook)
        } catch {
            addToLibraryState = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func performDownload(book: LibriVoxBook, modelContext: ModelContext) async {
        downloadState = .fetchingTracks
        do {
            let tracks = try await LibriVoxDownloadService.prepareDownload(projectID: book.id)
            let total = tracks.count
            downloadState = .downloading(completed: 0, total: total)
            tracker?.registerDownload(book: book, total: total, cancelHandler: { [weak self] in self?.cancelDownload() })

            // Cache tracks for future offline use
            book.cachedTracks = tracks.enumerated().map { i, t in
                CachedLibriVoxTrack(title: t.title, listenURL: t.listenURL, durationSeconds: t.durationSeconds, orderIndex: i)
            }
            try? modelContext.save()

            let audiobook = try await LibriVoxDownloadService.downloadAndImport(
                book: book,
                tracks: tracks,
                modelContext: modelContext
            ) { [weak self] completed, total in
                Task { @MainActor [weak self] in
                    self?.downloadState = .downloading(completed: completed, total: total)
                    self?.tracker?.updateDownloadProgress(bookId: book.id, completed: completed, total: total)
                }
            }

            downloadState = .complete(audiobook)
            tracker?.completeDownload(bookId: book.id)
        } catch {
            if Task.isCancelled {
                downloadState = .idle
            } else {
                downloadState = .failed(error.localizedDescription)
            }
            tracker?.cancelOrFailDownload(bookId: book.id)
        }
    }

    /// Restore + download: the archived backup already holds the synced progress/moments and each
    /// track's remote URL, so we download in place (preserving playback state) rather than creating
    /// a new book.
    @MainActor
    private func performRestoreDownload(backup: Audiobook, book: LibriVoxBook, modelContext: ModelContext) async {
        downloadState = .fetchingTracks
        do {
            let total = backup.tracks.count
            downloadState = .downloading(completed: 0, total: total)
            tracker?.registerDownload(book: book, total: total, cancelHandler: { [weak self] in self?.cancelDownload() })

            try await LibriVoxDownloadService.downloadStreamedBook(
                audiobook: backup,
                modelContext: modelContext
            ) { [weak self] completed, total in
                Task { @MainActor [weak self] in
                    self?.downloadState = .downloading(completed: completed, total: total)
                    self?.tracker?.updateDownloadProgress(bookId: book.id, completed: completed, total: total)
                }
            }

            downloadState = .complete(backup)
            tracker?.completeDownload(bookId: book.id)
        } catch {
            if Task.isCancelled {
                downloadState = .idle
            } else {
                downloadState = .failed(error.localizedDescription)
            }
            tracker?.cancelOrFailDownload(bookId: book.id)
        }
    }
}
