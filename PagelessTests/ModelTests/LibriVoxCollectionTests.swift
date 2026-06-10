//
//  LibriVoxCollectionTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

struct LibriVoxCollectionTests {

    @Test func collectionsAreNonEmpty() {
        #expect(!LibriVoxCollection.all.isEmpty)
        for collection in LibriVoxCollection.all {
            #expect(collection.bookIDs.count >= 3, "Collection \(collection.id) is too thin to ship")
        }
    }

    @Test func collectionIDsAreUnique() {
        let ids = LibriVoxCollection.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func bookIDsAreUniqueWithinEachCollection() {
        for collection in LibriVoxCollection.all {
            #expect(Set(collection.bookIDs).count == collection.bookIDs.count,
                    "Collection \(collection.id) repeats a book ID")
        }
    }

    @Test func bookIDsAreNumericLibriVoxProjectIDs() {
        for collection in LibriVoxCollection.all {
            for id in collection.bookIDs {
                #expect(Int(id) != nil, "Collection \(collection.id) has non-numeric ID \(id)")
            }
        }
    }

    @Test func displayFieldsAreFilled() {
        for collection in LibriVoxCollection.all {
            #expect(!collection.title.isEmpty)
            #expect(!collection.subtitle.isEmpty)
            #expect(!collection.iconSystemName.isEmpty)
        }
    }
}
