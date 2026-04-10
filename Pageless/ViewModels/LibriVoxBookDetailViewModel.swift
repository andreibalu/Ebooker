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

    func startDownload(book: LibriVoxBook, modelContext: ModelContext) {
        guard !downloadState.isActive else { return }
        downloadTask = Task { [weak self] in
            await self?.performDownload(book: book, modelContext: modelContext)
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadState = .idle
    }

    @MainActor
    private func performDownload(book: LibriVoxBook, modelContext: ModelContext) async {
        downloadState = .fetchingTracks
        do {
            let tracks = try await LibriVoxDownloadService.prepareDownload(projectID: book.id)
            downloadState = .downloading(completed: 0, total: tracks.count)

            let audiobook = try await LibriVoxDownloadService.downloadAndImport(
                book: book,
                tracks: tracks,
                modelContext: modelContext
            ) { [weak self] completed, total in
                Task { @MainActor [weak self] in
                    self?.downloadState = .downloading(completed: completed, total: total)
                }
            }

            downloadState = .complete(audiobook)
        } catch {
            if Task.isCancelled {
                downloadState = .idle
            } else {
                downloadState = .failed(error.localizedDescription)
            }
        }
    }
}
