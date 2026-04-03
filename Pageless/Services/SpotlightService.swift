//
//  SpotlightService.swift
//  Pageless
//

import CoreSpotlight
import Foundation

enum SpotlightService {
    private static let domainIdentifier = "andreibaludev.pageless.audiobooks"

    static func index(_ audiobook: Audiobook) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .audio)
        attributeSet.title = audiobook.title
        attributeSet.contentDescription = audiobook.displayAuthor
        attributeSet.duration = NSNumber(value: audiobook.totalDuration)
        if let coverData = audiobook.coverArtData {
            attributeSet.thumbnailData = coverData
        }

        let item = CSSearchableItem(
            uniqueIdentifier: audiobook.id.uuidString,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )

        CSSearchableIndex.default().indexSearchableItems([item])
    }

    static func deindex(_ audiobook: Audiobook) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [audiobook.id.uuidString]
        )
    }

    static func reindexAll(_ audiobooks: [Audiobook]) {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domainIdentifier]
        ) { _ in
            let items = audiobooks.map { book -> CSSearchableItem in
                let attrs = CSSearchableItemAttributeSet(contentType: .audio)
                attrs.title = book.title
                attrs.contentDescription = book.displayAuthor
                attrs.duration = NSNumber(value: book.totalDuration)
                if let coverData = book.coverArtData {
                    attrs.thumbnailData = coverData
                }
                return CSSearchableItem(
                    uniqueIdentifier: book.id.uuidString,
                    domainIdentifier: domainIdentifier,
                    attributeSet: attrs
                )
            }
            CSSearchableIndex.default().indexSearchableItems(items)
        }
    }
}
