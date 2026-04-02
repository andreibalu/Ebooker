//
//  MomentNamingServiceLogicTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct MomentNamingServiceLogicTests {
    private let service = MomentNamingService()

    // MARK: - sanitizedQuoteLine

    @Test func sanitizedQuotePassesThroughNormalQuote() {
        let transcript = String(repeating: "word ", count: 30)
        let out = service.sanitizedQuoteLine("A memorable line from the story.", transcript: transcript)
        #expect(out == "A memorable line from the story.")
    }

    @Test func sanitizedQuoteStripsLeadingTrailingQuoteChars() {
        let transcript = String(repeating: "x", count: 50)
        let out = service.sanitizedQuoteLine("\"“”'Hello there'”\"", transcript: transcript)
        #expect(out == "Hello there")
    }

    @Test func sanitizedQuoteCollapsesInternalNewlines() {
        let transcript = String(repeating: "x", count: 50)
        let out = service.sanitizedQuoteLine("Line one\nLine two\r\nLine three", transcript: transcript)
        #expect(out == "Line one Line two Line three")
    }

    @Test func sanitizedQuoteFallsBackToFirstSentenceWhenTooLong() {
        let long = String(repeating: "z", count: 230)
        let transcript = String(repeating: "a", count: 1_000)
        let out = service.sanitizedQuoteLine(long, transcript: transcript)
        #expect(out.count <= 140)
        #expect(out.hasPrefix("z"))
    }

    @Test func sanitizedQuoteFallsBackWhenRatioExceeds45Percent() {
        // Short transcript so ratio triggers; long tail so fallback uses firstSentence → prefix(140), shorter than full quote.
        let transcript = "ab"
        let quote = "Hi." + String(repeating: "x", count: 220)
        let out = service.sanitizedQuoteLine(quote, transcript: transcript)
        #expect(out.count <= 140)
        #expect(out.count < quote.count)
    }

    @Test func sanitizedQuoteReturnsEmptyForEmptyInput() {
        let out = service.sanitizedQuoteLine("", transcript: "anything")
        #expect(out.isEmpty)
    }

    // MARK: - firstSentence

    @Test func firstSentenceExtractsUpToFirstPeriod() {
        let prefix = String(repeating: "a", count: 25)
        let text = prefix + ". trailing ignored here"
        let out = service.firstSentence(in: text, maxLength: 140)
        #expect(out == prefix + ".")
    }

    @Test func firstSentenceExtractsUpToExclamation() {
        let prefix = String(repeating: "b", count: 25)
        let text = prefix + "! more text"
        let out = service.firstSentence(in: text, maxLength: 140)
        #expect(out == prefix + "!")
    }

    @Test func firstSentenceTruncatesToMaxLengthWhenNoTerminator() {
        let text = "abcdefghijklmnopqrstuvwxyz"
        let out = service.firstSentence(in: text, maxLength: 10)
        #expect(out == "abcdefghij")
    }
}
