//
//  AudiobookFreeBookTests.swift
//  PagelessTests
//

import Testing
import Foundation
@testable import Pageless

struct AudiobookFreeBookTests {

    @Test func catalogIdCanBeSetAndRead() {
        let book = Audiobook(title: "Test", folderName: "test")
        book.catalogId = "librivox-pride-and-prejudice"
        #expect(book.catalogId == "librivox-pride-and-prejudice")
    }

}
