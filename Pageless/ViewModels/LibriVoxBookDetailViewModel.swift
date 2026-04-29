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
        Task { [weak self] in
            await self?.performAddToLibrary(book: book, modelContext: modelContext)
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
}
