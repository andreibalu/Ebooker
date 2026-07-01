//
//  LibriVoxBookDetailViewModelTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

@MainActor
struct LibriVoxBookDetailViewModelTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, LibriVoxBook.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeCatalogBook(id: String = "catalog-1") -> LibriVoxBook {
        LibriVoxBook(
            id: id,
            title: "The Book",
            authorDisplay: "The Author",
            bookDescription: "",
            language: "English",
            totalTimeSecs: 60
        )
    }

    private func makeAudiobook(downloaded: Bool, archived: Bool = false) -> Audiobook {
        let audiobook = Audiobook(
            title: "The Book",
            author: "The Author",
            folderName: UUID().uuidString,
            isFreeBook: true,
            catalogId: "catalog-1",
            isDownloaded: downloaded
        )
        audiobook.isArchived = archived
        return audiobook
    }

    private func makeManager() -> LibriVoxDownloadManager {
        LibriVoxDownloadManager(
            executor: .init { _, _ in },
            completionRemoval: { _ in }
        )
    }

    @Test func activeCatalogRequestObservesExistingManagerEntry() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let manager = makeManager()
        let book = makeCatalogBook()
        let existingRequest = LibriVoxDownloadManager.Request(
            catalogID: book.id,
            metadata: .init(title: book.title),
            target: .fresh
        )
        #expect(manager.start(request: existingRequest))
        let viewModel = LibriVoxBookDetailViewModel()

        try viewModel.requestDownload(
            book: book,
            modelContext: context,
            manager: manager
        )

        #expect(manager.entry(for: book.id)?.request == existingRequest)
    }

    @Test(arguments: DetailIdentityCase.allCases)
    func catalogIdentityDeterminesDownloadTarget(identityCase: DetailIdentityCase) throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing: Audiobook?
        switch identityCase {
        case .downloaded:
            existing = makeAudiobook(downloaded: true)
        case .streaming:
            existing = makeAudiobook(downloaded: false)
        case .archived:
            existing = makeAudiobook(downloaded: false, archived: true)
            existing?.currentTime = 42
        case .absent:
            existing = nil
        }
        if let existing {
            context.insert(existing)
            try context.save()
        }
        let manager = makeManager()
        let viewModel = LibriVoxBookDetailViewModel()

        try viewModel.requestDownload(
            book: makeCatalogBook(),
            modelContext: context,
            manager: manager
        )

        if let existing {
            #expect(viewModel.libraryAudiobook === existing)
        } else {
            #expect(viewModel.libraryAudiobook == nil)
        }
        switch identityCase {
        case .downloaded:
            #expect(manager.entry(for: "catalog-1") == nil)
        case .streaming, .archived:
            #expect(manager.entry(for: "catalog-1")?.target == .existing(audiobookID: existing!.id))
        case .absent:
            #expect(manager.entry(for: "catalog-1")?.target == .fresh)
        }
        if identityCase == .archived {
            #expect(existing?.isArchived == true)
            #expect(existing?.currentTime == 42)
        }
    }

    @Test func refreshFailureClearsPreviouslyResolvedIdentity() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = makeAudiobook(downloaded: true)
        var lookupCount = 0
        let viewModel = LibriVoxBookDetailViewModel(identityLookup: { _, _ in
            lookupCount += 1
            if lookupCount == 1 {
                return .init(audiobook: existing, classification: .downloadedActive)
            }
            throw PromotionFailure.injected
        })
        let book = makeCatalogBook()

        viewModel.refreshIdentity(book: book, modelContext: context)
        #expect(viewModel.libraryAudiobook === existing)

        viewModel.refreshIdentity(book: book, modelContext: context)

        #expect(viewModel.libraryAudiobook == nil)
        #expect(viewModel.requestErrorMessage != nil)
    }

    @Test func addReusesDownloadedAndStreamingRows() async throws {
        for downloaded in [true, false] {
            let container = try makeContainer()
            let context = container.mainContext
            let existing = makeAudiobook(downloaded: downloaded)
            context.insert(existing)
            try context.save()
            let viewModel = LibriVoxBookDetailViewModel()

            await viewModel.addToLibrary(book: makeCatalogBook(), modelContext: context)

            #expect(viewModel.libraryAudiobook === existing)
            #expect(try context.fetch(FetchDescriptor<Audiobook>()).count == 1)
        }
    }

    @Test func addReusesAndActivatesArchivedRow() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = makeAudiobook(downloaded: false, archived: true)
        existing.currentTime = 42
        context.insert(existing)
        try context.save()
        let viewModel = LibriVoxBookDetailViewModel()

        await viewModel.addToLibrary(book: makeCatalogBook(), modelContext: context)

        #expect(viewModel.libraryAudiobook === existing)
        #expect(!existing.isArchived)
        #expect(!existing.isDownloaded)
        #expect(existing.currentTime == 42)
        #expect(try context.fetch(FetchDescriptor<Audiobook>()).count == 1)
    }
}

enum DetailIdentityCase: CaseIterable, Sendable {
    case downloaded
    case streaming
    case archived
    case absent
}

private enum PromotionFailure: Error {
    case injected
}
