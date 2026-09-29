//
//  LibriVoxCollectionTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

struct LibriVoxCollectionTests {

    @Test func curatedCollectionsAreShippable() {
        #expect(!LibriVoxCollection.all.isEmpty)
        let ids = LibriVoxCollection.all.map(\.id)
        #expect(Set(ids).count == ids.count)

        for collection in LibriVoxCollection.all {
            #expect(collection.bookIDs.count >= 3, "Collection \(collection.id) is too thin to ship")
            #expect(Set(collection.bookIDs).count == collection.bookIDs.count,
                    "Collection \(collection.id) repeats a book ID")
            for id in collection.bookIDs {
                #expect(Int(id) != nil, "Collection \(collection.id) has non-numeric ID \(id)")
            }
            #expect(!collection.title.isEmpty)
            #expect(!collection.subtitle.isEmpty)
            #expect(!collection.iconSystemName.isEmpty)
        }
    }
}
