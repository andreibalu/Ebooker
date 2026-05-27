//
//  FreeBookDownloadServiceTests.swift
//  PagelessTests
//

import Testing
import Foundation
import SwiftData
@testable import Pageless

@MainActor
struct FreeBookDownloadServiceTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeSampleCatalogEntry() -> FreeBookCatalogEntry {
        FreeBookCatalogEntry(
            id: "test-book",
            title: "Test Book",
            author: "Test Author",
            description: "A test book.",
            coverAssetName: nil,
            totalDurationSeconds: 3600,
            downloadSizeMB: 25.0,
            tracks: [
                FreeBookTrackEntry(
                    id: "test-ch01",
                    title: "Chapter 1",
                    fileName: "chapter_01.mp3",
                    downloadURL: "https://example.com/ch01.mp3",
                    durationSeconds: 1800,
                    orderIndex: 0
                ),
                FreeBookTrackEntry(
                    id: "test-ch02",
                    title: "Chapter 2",
                    fileName: "chapter_02.mp3",
                    downloadURL: "https://example.com/ch02.mp3",
                    durationSeconds: 1800,
                    orderIndex: 1
                )
            ]
        )
    }

    // MARK: - State Tests

    @Test func initialStateHasNoActiveDownloads() {
        let service = FreeBookDownloadService()
        #expect(service.activeDownloads.isEmpty)
    }

    @Test func initialStateHasNoProgress() {
        let service = FreeBookDownloadService()
        #expect(service.downloadProgress.isEmpty)
    }

    @Test func initialStateHasNoErrors() {
        let service = FreeBookDownloadService()
        #expect(service.downloadErrors.isEmpty)
    }

    // MARK: - Mock Protocol Tests

    @Test func mockStartDownloadAddsToActiveDownloads() {
        let mock = MockFreeBookDownloadService()
        let entry = makeSampleCatalogEntry()
        mock.startDownload(entry: entry)
        #expect(mock.activeDownloads.contains("test-book"))
    }

    @Test func mockCancelDownloadRemovesFromActiveDownloads() {
        let mock = MockFreeBookDownloadService()
        let entry = makeSampleCatalogEntry()
        mock.startDownload(entry: entry)
        mock.cancelDownload(catalogId: "test-book")
        #expect(!mock.activeDownloads.contains("test-book"))
    }

    @Test func mockStartDownloadSetsInitialProgress() {
        let mock = MockFreeBookDownloadService()
        let entry = makeSampleCatalogEntry()
        mock.startDownload(entry: entry)
        #expect(mock.downloadProgress["test-book"] == 0.0)
    }

    // MARK: - Finalization Tests

    @Test func finalizationCreatesAudiobookWithCatalogId() throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()
        let folderName = "test-folder-uuid"

        let service = FreeBookDownloadService()
        try service.finalizeDownload(catalogEntry: entry, folderName: folderName, coverData: nil, modelContext: context)

        let audiobooks = try context.fetch(FetchDescriptor<Audiobook>())
        #expect(audiobooks.count == 1)
        #expect(audiobooks.first?.catalogId == "test-book")
    }

    @Test func finalizationCreatesCorrectNumberOfTracks() throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()

        let service = FreeBookDownloadService()
        try service.finalizeDownload(catalogEntry: entry, folderName: "folder", coverData: nil, modelContext: context)

        let tracks = try context.fetch(FetchDescriptor<AudioTrack>())
        #expect(tracks.count == 2)
    }

    @Test func finalizationSetsIsFreeBookTrue() throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()

        let service = FreeBookDownloadService()
        try service.finalizeDownload(catalogEntry: entry, folderName: "folder", coverData: nil, modelContext: context)

        let audiobooks = try context.fetch(FetchDescriptor<Audiobook>())
        #expect(audiobooks.first?.isFreeBook == true)
    }

    @Test func finalizationUsesCorrectStoredFileNames() throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()

        let service = FreeBookDownloadService()
        try service.finalizeDownload(catalogEntry: entry, folderName: "folder", coverData: nil, modelContext: context)

        let tracks = try context.fetch(FetchDescriptor<AudioTrack>())
        let sortedTracks = tracks.sorted { $0.orderIndex < $1.orderIndex }
        #expect(sortedTracks[0].storedFileName == "001-chapter_01.mp3")
        #expect(sortedTracks[1].storedFileName == "002-chapter_02.mp3")
    }
}
