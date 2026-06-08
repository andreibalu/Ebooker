//
//  LibriVoxCatalogSync.swift
//  Pageless
//

import Foundation
import SwiftData

enum LibriVoxCatalogSync {
    private static let lastSyncKey = "librivox.lastCatalogSyncDate"
    private static let syncedCountKey = "librivox.syncedBookCount"

    static var lastSyncDate: Date? {
        let ts = UserDefaults.standard.double(forKey: lastSyncKey)
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    static var syncedBookCount: Int {
        UserDefaults.standard.integer(forKey: syncedCountKey)
    }

    /// Runs a full sync if never synced before, or an incremental sync if the last sync
    /// was more than 24 hours ago. Skips entirely if synced within the last 24 hours.
    static func syncIfNeeded(
        modelContext: ModelContext,
        onProgress: @escaping (Int) -> Void
    ) async throws {
        if let last = lastSyncDate {
            let age = Date.now.timeIntervalSince(last)
            if age < 86_400 { return } // synced within 24 h, skip
            try await incrementalSync(since: last, modelContext: modelContext, onProgress: onProgress)
        } else {
            try await fullSync(modelContext: modelContext, onProgress: onProgress)
        }
    }

    /// Force a full re-sync regardless of last sync date.
    static func forceFullSync(
        modelContext: ModelContext,
        onProgress: @escaping (Int) -> Void
    ) async throws {
        try await fullSync(modelContext: modelContext, onProgress: onProgress)
    }

    /// Upserts a small set of pre-fetched API books into the store and saves.
    /// Used by the featured-classics preload so the curated rows exist before the
    /// full catalog sync runs. Reuses the same `upsert` path, so a later full sync
    /// matches these rows by `id` and does not create duplicates.
    static func seed(_ apiBooks: [LibriVoxAPIBook], into context: ModelContext) throws {
        guard !apiBooks.isEmpty else { return }
        for apiBook in apiBooks {
            try upsert(apiBook, into: context)
        }
        try context.save()
    }

    // MARK: - Private

    private static func fullSync(
        modelContext: ModelContext,
        onProgress: @escaping (Int) -> Void
    ) async throws {
        // Pre-load all existing IDs so we can skip re-inserting them on re-syncs.
        let existingIDs = Set(
            (try modelContext.fetch(FetchDescriptor<LibriVoxBook>())).map { $0.id }
        )

        var offset = 0
        var totalFetched = 0

        while true {
            let page = try await fetchPageWithRetry(offset: offset)
            guard !page.isEmpty else { break }

            for apiBook in page {
                if existingIDs.contains(apiBook.id) { continue }
                modelContext.insert(LibriVoxBook(
                    id: apiBook.id,
                    title: apiBook.title,
                    authorDisplay: apiBook.authorDisplay,
                    bookDescription: apiBook.description,
                    language: apiBook.language,
                    totalTimeSecs: apiBook.totalTimeSecs,
                    genres: apiBook.genreNames,
                    coverThumbnailURLString: apiBook.coverartThumbnail,
                    librivoxURLString: apiBook.urlLibrivox,
                    internetArchiveURLString: apiBook.urlIarchive,
                    rssURLString: apiBook.urlRss
                ))
            }

            try modelContext.save()
            totalFetched += page.count
            UserDefaults.standard.set(existingIDs.count + totalFetched, forKey: syncedCountKey)
            onProgress(totalFetched)

            if page.count < 50 { break }
            offset += page.count
        }

        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastSyncKey)
    }

    private static func incrementalSync(
        since: Date,
        modelContext: ModelContext,
        onProgress: @escaping (Int) -> Void
    ) async throws {
        let updates = try await LibriVoxAPIClient.fetchCatalogSince(timestamp: since)
        guard !updates.isEmpty else {
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastSyncKey)
            return
        }

        var upserted = 0
        for apiBook in updates {
            try upsert(apiBook, into: modelContext)
            upserted += 1
            if upserted % 50 == 0 {
                try modelContext.save()
                onProgress(upserted)
            }
        }

        try modelContext.save()
        onProgress(upserted)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastSyncKey)
    }

    /// Fetches one catalog page, retrying briefly on a transient failure so a single flaky
    /// response from the LibriVox feed doesn't abort the whole multi-thousand-book sync.
    /// Cancellation and offline conditions are not retried — they propagate immediately.
    private static func fetchPageWithRetry(offset: Int, attempts: Int = 3) async throws -> [LibriVoxAPIBook] {
        var lastError: Error?
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            do {
                return try await LibriVoxAPIClient.fetchCatalogPage(offset: offset)
            } catch let urlError as URLError where urlError.code == .notConnectedToInternet {
                throw urlError // offline — no point retrying
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                // Linear backoff: 0.5s, 1.0s — short enough to stay responsive. No sleep after
                // the final attempt so the error surfaces immediately.
                if attempt < attempts - 1 {
                    try? await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
                }
            }
        }
        throw lastError ?? LibriVoxAPIError.unreadableResponse
    }

    private static func upsert(_ apiBook: LibriVoxAPIBook, into context: ModelContext) throws {
        let id = apiBook.id
        let predicate = #Predicate<LibriVoxBook> { $0.id == id }
        let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first

        if let book = existing {
            book.title = apiBook.title
            book.authorDisplay = apiBook.authorDisplay
            book.bookDescription = apiBook.description
            book.language = apiBook.language
            book.totalTimeSecs = apiBook.totalTimeSecs
            book.genres = apiBook.genreNames
            book.coverThumbnailURLString = apiBook.coverartThumbnail
            book.librivoxURLString = apiBook.urlLibrivox
            book.internetArchiveURLString = apiBook.urlIarchive
            book.rssURLString = apiBook.urlRss
            book.lastSyncedAt = .now
        } else {
            context.insert(LibriVoxBook(
                id: apiBook.id,
                title: apiBook.title,
                authorDisplay: apiBook.authorDisplay,
                bookDescription: apiBook.description,
                language: apiBook.language,
                totalTimeSecs: apiBook.totalTimeSecs,
                genres: apiBook.genreNames,
                coverThumbnailURLString: apiBook.coverartThumbnail,
                librivoxURLString: apiBook.urlLibrivox,
                internetArchiveURLString: apiBook.urlIarchive,
                rssURLString: apiBook.urlRss
            ))
        }
    }
}
