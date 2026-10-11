//
//  AudiobookAdditionalTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

struct AudiobookAdditionalTests {
    @Test func discardRecapClearsWhenTrackMismatches() {
        let book = Audiobook(title: "R", folderName: "r", totalDuration: 100)
        book.progressTrackIndex = 1
        book.progressTime = 50
        book.storeProgressRecap(text: "stale", headline: "h", anchorTrackIndex: 0, anchorTime: 50)
        book.discardProgressRecapIfAnchorMismatched()
        #expect(book.progressRecapText == nil)
    }
}
