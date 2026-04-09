//
//  FreeBookCatalogEntryTests.swift
//  PagelessTests
//

import Testing
import Foundation
@testable import Pageless

struct FreeBookCatalogEntryTests {
    private let sampleJSON = """
    {
        "id": "librivox-alice-in-wonderland",
        "title": "Alice's Adventures in Wonderland",
        "author": "Lewis Carroll",
        "description": "A young girl falls down a rabbit hole into a fantasy world.",
        "coverAssetName": "cover-alice",
        "totalDurationSeconds": 10200,
        "downloadSizeMB": 85.5,
        "tracks": [
            {
                "id": "alice-ch01",
                "title": "Chapter 1 - Down the Rabbit-Hole",
                "fileName": "chapter_01.mp3",
                "downloadURL": "https://archive.org/download/alice/chapter_01.mp3",
                "durationSeconds": 1020,
                "orderIndex": 0
            },
            {
                "id": "alice-ch02",
                "title": "Chapter 2 - The Pool of Tears",
                "fileName": "chapter_02.mp3",
                "downloadURL": "https://archive.org/download/alice/chapter_02.mp3",
                "durationSeconds": 980,
                "orderIndex": 1
            }
        ]
    }
    """.data(using: .utf8)!

    @Test func decodesFromValidJSON() throws {
        let entry = try JSONDecoder().decode(FreeBookCatalogEntry.self, from: sampleJSON)
        #expect(entry.id == "librivox-alice-in-wonderland")
        #expect(entry.title == "Alice's Adventures in Wonderland")
        #expect(entry.author == "Lewis Carroll")
        #expect(entry.description == "A young girl falls down a rabbit hole into a fantasy world.")
        #expect(entry.coverAssetName == "cover-alice")
        #expect(entry.totalDurationSeconds == 10200)
        #expect(entry.downloadSizeMB == 85.5)
    }

    @Test func tracksDecodeCorrectly() throws {
        let entry = try JSONDecoder().decode(FreeBookCatalogEntry.self, from: sampleJSON)
        #expect(entry.tracks.count == 2)
        #expect(entry.tracks[0].id == "alice-ch01")
        #expect(entry.tracks[0].title == "Chapter 1 - Down the Rabbit-Hole")
        #expect(entry.tracks[0].fileName == "chapter_01.mp3")
        #expect(entry.tracks[0].orderIndex == 0)
        #expect(entry.tracks[1].orderIndex == 1)
    }

    @Test func encodesAndDecodesRoundTrip() throws {
        let original = try JSONDecoder().decode(FreeBookCatalogEntry.self, from: sampleJSON)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FreeBookCatalogEntry.self, from: encoded)
        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.author == original.author)
        #expect(decoded.tracks.count == original.tracks.count)
        #expect(decoded.downloadSizeMB == original.downloadSizeMB)
    }

    @Test func allFieldsPopulated() throws {
        let entry = try JSONDecoder().decode(FreeBookCatalogEntry.self, from: sampleJSON)
        #expect(!entry.id.isEmpty)
        #expect(!entry.title.isEmpty)
        #expect(!entry.author.isEmpty)
        #expect(!entry.description.isEmpty)
        #expect(entry.totalDurationSeconds > 0)
        #expect(entry.downloadSizeMB > 0)
        #expect(!entry.tracks.isEmpty)
    }

    @Test func identifiableIdMatchesExpected() throws {
        let entry = try JSONDecoder().decode(FreeBookCatalogEntry.self, from: sampleJSON)
        #expect(entry.id == "librivox-alice-in-wonderland")
    }
}
