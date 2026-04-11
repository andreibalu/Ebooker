//
//  StreamedBookDownloadViewModel.swift
//  Pageless
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class StreamedBookDownloadViewModel {
    enum State {
        case idle
        case downloading(completed: Int, total: Int)
        case complete
        case failed(String)
    }

    var state: State = .idle
    private var task: Task<Void, Never>?

    func startDownload(audiobook: Audiobook, modelContext: ModelContext) {
        guard case .idle = state else { return }
        guard NetworkMonitor.shared.isConnected else {
            state = .failed("You're offline. Connect to the internet to download.")
            return
        }
        task = Task { [weak self] in
            await self?.performDownload(audiobook: audiobook, modelContext: modelContext)
        }
    }

    private func performDownload(audiobook: Audiobook, modelContext: ModelContext) async {
        state = .downloading(completed: 0, total: audiobook.tracks.count)
        do {
            try await LibriVoxDownloadService.downloadStreamedBook(
                audiobook: audiobook,
                modelContext: modelContext
            ) { [weak self] completed, total in
                Task { @MainActor in
                    self?.state = .downloading(completed: completed, total: total)
                }
            }
            state = .complete
        } catch {
            if Task.isCancelled {
                state = .idle
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }
}
