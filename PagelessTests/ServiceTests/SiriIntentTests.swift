//
//  SiriIntentTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

/// Tests for the Siri App Intent integration:
/// - PlayLatestBookIntent sets the UserDefaults flag
/// - The latest-book fetch descriptor selects the correct audiobook
@MainActor
struct SiriIntentTests {

    private static let intentFlagKey = "intent.playLatestBook"

    // MARK: - PlayLatestBookIntent

    @Test func intentPerformSetsUserDefaultsFlag() async throws {
        UserDefaults.standard.removeObject(forKey: Self.intentFlagKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.intentFlagKey) }

        let intent = PlayLatestBookIntent()
        _ = try await intent.perform()

        #expect(UserDefaults.standard.bool(forKey: Self.intentFlagKey) == true)
    }

    @Test func intentFlagIsAbsentBeforePerform() {
        UserDefaults.standard.removeObject(forKey: Self.intentFlagKey)
        #expect(UserDefaults.standard.bool(forKey: Self.intentFlagKey) == false)
    }

    // MARK: - Latest-book fetch logic (mirrors handlePendingIntent in PagelessApp)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Audiobook.self, AudioTrack.self, Moment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func fetchLatest(from context: ModelContext) throws -> Audiobook? {
        var descriptor = FetchDescriptor<Audiobook>(
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @Test func fetchReturnsNilForEmptyLibrary() throws {
        let context = try makeContainer().mainContext
        #expect(try fetchLatest(from: context) == nil)
    }

    @Test func fetchReturnsSingleBook() throws {
        let context = try makeContainer().mainContext
        let book = Audiobook(title: "Only Book", folderName: "only", totalDuration: 100)
        book.lastPlayedAt = Date(timeIntervalSinceNow: -300)
        context.insert(book)

        let result = try fetchLatest(from: context)
        #expect(result?.title == "Only Book")
    }

    @Test func fetchSelectsMostRecentlyPlayedBook() throws {
        let context = try makeContainer().mainContext

        let older = Audiobook(title: "Older Book", folderName: "older", totalDuration: 100)
        older.lastPlayedAt = Date(timeIntervalSinceNow: -7200) // 2 hours ago

        let newer = Audiobook(title: "Newer Book", folderName: "newer", totalDuration: 100)
        newer.lastPlayedAt = Date(timeIntervalSinceNow: -60) // 1 minute ago

        context.insert(older)
        context.insert(newer)

        #expect(try fetchLatest(from: context)?.title == "Newer Book")
    }

    @Test func fetchSelectsMostRecentAmongManyBooks() throws {
        let context = try makeContainer().mainContext

        let dates: [TimeInterval] = [-86400, -3600, -300, -7200, -600]
        for (i, offset) in dates.enumerated() {
            let book = Audiobook(title: "Book \(i)", folderName: "book\(i)", totalDuration: 100)
            book.lastPlayedAt = Date(timeIntervalSinceNow: offset)
            context.insert(book)
        }
        // -300 seconds ago is the most recent
        #expect(try fetchLatest(from: context)?.title == "Book 2")
    }

    @Test func fetchPreferredPlayedBookOverNeverPlayedBook() throws {
        let context = try makeContainer().mainContext

        let neverPlayed = Audiobook(title: "Never Played", folderName: "new", totalDuration: 100)
        // lastPlayedAt = nil

        let played = Audiobook(title: "Played Book", folderName: "played", totalDuration: 100)
        played.lastPlayedAt = Date(timeIntervalSinceNow: -60)

        // Insert never-played first so insertion order can't be the reason it wins
        context.insert(neverPlayed)
        context.insert(played)

        #expect(try fetchLatest(from: context)?.title == "Played Book")
    }

    @Test func fetchLimitIsOne() throws {
        let context = try makeContainer().mainContext

        for i in 0..<5 {
            let book = Audiobook(title: "Book \(i)", folderName: "b\(i)", totalDuration: 100)
            book.lastPlayedAt = Date(timeIntervalSinceNow: Double(-i * 60))
            context.insert(book)
        }

        var descriptor = FetchDescriptor<Audiobook>(
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)

        #expect(results.count == 1)
    }
}
