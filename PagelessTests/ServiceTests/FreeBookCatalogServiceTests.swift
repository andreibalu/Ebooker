//
//  FreeBookCatalogServiceTests.swift
//  PagelessTests
//

import Testing
import Foundation
@testable import Pageless

struct FreeBookCatalogServiceTests {
    @Test func loadCatalogReturnsNonEmptyArray() {
        let entries = FreeBookCatalogService.allEntries()
        #expect(!entries.isEmpty)
    }

    @Test func loadCatalogEntriesHaveValidFields() {
        let entries = FreeBookCatalogService.allEntries()
        for entry in entries {
            #expect(!entry.id.isEmpty)
            #expect(!entry.title.isEmpty)
            #expect(!entry.author.isEmpty)
            #expect(!entry.description.isEmpty)
            #expect(entry.totalDurationSeconds > 0)
            #expect(entry.downloadSizeMB > 0)
        }
    }

    @Test func allEntriesHaveTracks() {
        let entries = FreeBookCatalogService.allEntries()
        for entry in entries {
            #expect(!entry.tracks.isEmpty, "Entry '\(entry.title)' has no tracks")
        }
    }

    @Test func allTracksDurationIsPositive() {
        let entries = FreeBookCatalogService.allEntries()
        for entry in entries {
            for track in entry.tracks {
                #expect(track.durationSeconds > 0, "Track '\(track.title)' in '\(entry.title)' has non-positive duration")
            }
        }
    }

    @Test func availableEntriesExcludesDownloadedIds() {
        let entries = FreeBookCatalogService.allEntries()
        guard let firstId = entries.first?.id else { return }
        let available = FreeBookCatalogService.availableEntries(excluding: Set([firstId]))
        #expect(available.count == entries.count - 1)
        #expect(!available.contains(where: { $0.id == firstId }))
    }

    @Test func availableEntriesReturnsAllWhenNoneDownloaded() {
        let entries = FreeBookCatalogService.allEntries()
        let available = FreeBookCatalogService.availableEntries(excluding: Set())
        #expect(available.count == entries.count)
    }

    @Test func allEntriesHaveUniqueIds() {
        let entries = FreeBookCatalogService.allEntries()
        let ids = entries.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "Catalog contains duplicate IDs")
    }
}
