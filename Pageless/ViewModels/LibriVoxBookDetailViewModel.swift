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

    private var downloadTask: Task<Void, Never>?
    private weak var tracker: BrowseLibriVoxViewModel?
    private var trackedBookId: String?

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

    @MainActor
    private func performDownload(book: LibriVoxBook, modelContext: ModelContext) async {
        downloadState = .fetchingTracks
        do {
            let tracks = try await LibriVoxDownloadService.prepareDownload(projectID: book.id)
            let total = tracks.count
            downloadState = .downloading(completed: 0, total: total)
            tracker?.registerDownload(book: book, total: total)

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
