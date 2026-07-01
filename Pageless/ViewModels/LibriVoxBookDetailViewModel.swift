//
//  LibriVoxBookDetailViewModel.swift
//  Pageless
//

import Foundation
import Observation
import SwiftData

/// Resolves persisted LibriVox identity and translates detail actions into shared-manager requests.
/// Download lifecycle and progress deliberately live in `LibriVoxDownloadManager`, not this screen.
@MainActor
@Observable
final class LibriVoxBookDetailViewModel {
    typealias IdentityLookup = @MainActor (
        String,
        ModelContext
    ) throws -> FreeBookIdentityService.Match?

    enum AddToLibraryState {
        case idle
        case loading
        case complete(Audiobook)
        case failed(String)
    }

    private(set) var libraryAudiobook: Audiobook?
    var addToLibraryState: AddToLibraryState = .idle
    var requestErrorMessage: String?
    @ObservationIgnored private let identityLookup: IdentityLookup

    init(identityLookup: @escaping IdentityLookup) {
        self.identityLookup = identityLookup
    }

    convenience init() {
        self.init(identityLookup: { catalogID, modelContext in
            try FreeBookIdentityService.match(catalogId: catalogID, modelContext: modelContext)
        })
    }

    var isActiveInLibrary: Bool {
        guard let libraryAudiobook else { return false }
        return !libraryAudiobook.isArchived
    }

    var isDownloaded: Bool {
        isActiveInLibrary && libraryAudiobook?.isDownloaded == true
    }

    func refreshIdentity(book: LibriVoxBook, modelContext: ModelContext) {
        do {
            let match = try identityLookup(book.id, modelContext)
            libraryAudiobook = match?.audiobook
            requestErrorMessage = nil
        } catch {
            libraryAudiobook = nil
            requestErrorMessage = error.localizedDescription
        }
    }

    func requestDownload(
        book: LibriVoxBook,
        modelContext: ModelContext,
        manager: LibriVoxDownloadManager
    ) throws {
        if manager.entry(for: book.id) != nil {
            return
        }

        let match = try identityLookup(book.id, modelContext)
        libraryAudiobook = match?.audiobook

        if match?.classification == .downloadedActive {
            return
        }

        let target: LibriVoxDownloadManager.Target
        if let audiobook = match?.audiobook {
            target = .existing(audiobookID: audiobook.id)
        } else {
            target = .fresh
        }
        let request = LibriVoxDownloadManager.Request(
            catalogID: book.id,
            metadata: .init(title: book.title),
            target: target
        )
        requestErrorMessage = nil
        manager.start(request: request)
    }

    func startDownload(
        book: LibriVoxBook,
        modelContext: ModelContext,
        manager: LibriVoxDownloadManager
    ) {
        do {
            try requestDownload(book: book, modelContext: modelContext, manager: manager)
        } catch {
            requestErrorMessage = error.localizedDescription
        }
    }

    func addToLibrary(book: LibriVoxBook, modelContext: ModelContext) async {
        guard !isAdding else { return }
        addToLibraryState = .loading
        do {
            if let match = try identityLookup(book.id, modelContext) {
                let audiobook: Audiobook
                if match.classification == .archived {
                    audiobook = try await StreamingLibraryService.addToLibrary(
                        book: book,
                        tracks: [],
                        modelContext: modelContext
                    )
                } else {
                    audiobook = match.audiobook
                }
                libraryAudiobook = audiobook
                addToLibraryState = .complete(audiobook)
                return
            }

            let cached: [CachedLibriVoxTrack]
            if let existing = book.cachedTracks {
                cached = existing
            } else {
                guard NetworkMonitor.shared.isConnected else {
                    addToLibraryState = .failed(
                        "Connect to the internet to load track info for this book."
                    )
                    return
                }
                let apiTracks = try await LibriVoxAPIClient.fetchTracks(projectID: book.id)
                guard !apiTracks.isEmpty else {
                    addToLibraryState = .failed("This book has no available tracks.")
                    return
                }
                cached = apiTracks.enumerated().map { index, track in
                    CachedLibriVoxTrack(
                        title: track.title,
                        listenURL: track.listenURL,
                        durationSeconds: track.durationSeconds,
                        orderIndex: index
                    )
                }
                book.cachedTracks = cached
                try modelContext.save()
            }

            let audiobook = try await StreamingLibraryService.addToLibrary(
                book: book,
                tracks: cached,
                modelContext: modelContext
            )
            libraryAudiobook = audiobook
            addToLibraryState = .complete(audiobook)
        } catch {
            addToLibraryState = .failed(error.localizedDescription)
        }
    }

    private var isAdding: Bool {
        if case .loading = addToLibraryState { return true }
        return false
    }
}
