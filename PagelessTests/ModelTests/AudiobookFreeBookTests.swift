//
//  AudiobookFreeBookTests.swift
//  PagelessTests
//

import Testing
import Foundation
@testable import Pageless

struct AudiobookFreeBookTests {
    @Test func isFreeBookDefaultsToFalse() {
        let book = Audiobook(title: "Test", folderName: "test")
        #expect(book.isFreeBook == false)
    }

    @Test func isFreeBookCanBeSet() {
        let book = Audiobook(title: "Test", folderName: "test")
        book.isFreeBook = true
        #expect(book.isFreeBook == true)
        book.isFreeBook = false
        #expect(book.isFreeBook == false)
    }

    @Test func catalogIdDefaultsToNil() {
        let book = Audiobook(title: "Test", folderName: "test")
        #expect(book.catalogId == nil)
    }

    @Test func catalogIdCanBeSetAndRead() {
        let book = Audiobook(title: "Test", folderName: "test")
        book.catalogId = "librivox-pride-and-prejudice"
        #expect(book.catalogId == "librivox-pride-and-prejudice")
    }

    @Test func isFreeBookPersistsThroughInit() {
        let book = Audiobook(title: "Free Book", folderName: "test", isFreeBook: true)
        #expect(book.isFreeBook == true)
    }

    @Test func catalogIdPersistsThroughInit() {
        let book = Audiobook(title: "Free Book", folderName: "test", catalogId: "my-catalog-id")
        #expect(book.catalogId == "my-catalog-id")
    }
}
