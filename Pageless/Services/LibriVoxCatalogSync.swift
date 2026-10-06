//
//  LibriVoxCatalogSync.swift
//  Pageless
//
//  The 20k-book LibriVox catalog cache. Pages are fetched off the main actor and
//  committed one 50-book page at a time by `LibriVoxCatalogStore`, a `@ModelActor`
//  with its own background `ModelContext`. After every committed page the next
//  offset is persisted, so a pause (app backgrounded) or a failure resumes from the
//  last completed page instead of restarting at offset 0.
//

import Foundation
import os
import SwiftData

/// Progress reported after each committed page.
nonisolated struct LibriVoxSyncProgress: Sendable, Equatable {
    /// Distinct catalog rows now stored locally.
    var savedCount: Int
    /// Books written by this run (new or refreshed).
    var processedThisRun: Int
}

nonisolated enum LibriVoxSyncOutcome: Sendable, Equatable {
    /// Synced within the last 24 h; nothing fetched.
    case skipped
    /// A full or incremental pass finished.
    case completed(processed: Int)
    /// Stopped cleanly between pages because a pause was requested.
    case paused
}

/// Thread-safe "stop after the current page" flag. The view model raises it when the
/// app enters the background; the sync loop checks it after each committed page.
nonisolated final class LibriVoxSyncPauseFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)
    var isRaised: Bool { state.withLock { $0 } }
    func raise() { state.withLock { $0 = true } }
}

/// The sync's persisted bookkeeping. `UserDefaults` is thread-safe; tests pass a
/// throwaway suite so they never touch the app's real cursor.
nonisolated struct LibriVoxSyncCheckpoint: @unchecked Sendable {
    let defaults: UserDefaults

    static var standard: LibriVoxSyncCheckpoint { LibriVoxSyncCheckpoint(defaults: .standard) }

    private static let lastSyncKey = "librivox.lastCatalogSyncDate"
    private static let syncedCountKey = "librivox.syncedBookCount"
    /// Rows cached before the API client sent extended=1 have no genre data (the feed
    /// ignored fields[]=genres without it). One forced full sync backfills them in place.
    private static let genresBackfillKey = "librivox.genresBackfillDone"
    /// Offset of the next full-sync page. Present only while a full pass is incomplete.
    private static let cursorKey = "librivox.fullSyncCursor"

    var lastSyncDate: Date? {
        let ts = defaults.double(forKey: Self.lastSyncKey)
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    var syncedBookCount: Int { defaults.integer(forKey: Self.syncedCountKey) }

    var genresBackfillDone: Bool { defaults.bool(forKey: Self.genresBackfillKey) }

    /// Where the next full pass starts. 0 when no pass is in progress.
    var resumeOffset: Int { max(0, defaults.integer(forKey: Self.cursorKey)) }

    /// Partial pages, curated seeds, and remote-search results never enable local-only
    /// search. A complete full pass (including the one-time genres backfill) does.
    var isLocalSearchReady: Bool { lastSyncDate != nil && genresBackfillDone }

    func recordPage(nextOffset: Int, savedCount: Int) {
        defaults.set(nextOffset, forKey: Self.cursorKey)
        defaults.set(savedCount, forKey: Self.syncedCountKey)
    }

    func recordSavedCount(_ count: Int) {
        defaults.set(count, forKey: Self.syncedCountKey)
    }

    func markFullPassComplete(total: Int, at date: Date = .now) {
        defaults.removeObject(forKey: Self.cursorKey)
        defaults.set(total, forKey: Self.syncedCountKey)
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastSyncKey)
        defaults.set(true, forKey: Self.genresBackfillKey)
    }

    func markIncrementalComplete(total: Int?, at date: Date = .now) {
        if let total { defaults.set(total, forKey: Self.syncedCountKey) }
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastSyncKey)
    }
}

/// Page sources, injectable so tests drive the sync without the network.
nonisolated struct LibriVoxCatalogFeed: Sendable {
    var fullPage: @Sendable (_ offset: Int) async throws -> [LibriVoxAPIBook]
    var sincePage: @Sendable (_ since: Date, _ offset: Int) async throws -> [LibriVoxAPIBook]

    static let live = LibriVoxCatalogFeed(
        fullPage: { offset in try await LibriVoxAPIClient.fetchCatalogPage(offset: offset) },
        sincePage: { since, offset in
            try await LibriVoxAPIClient.fetchCatalogSincePage(timestamp: since, offset: offset)
        }
    )
}

nonisolated enum LibriVoxCatalogSync {
    static let pageSize = 50

    static var lastSyncDate: Date? { LibriVoxSyncCheckpoint.standard.lastSyncDate }
    static var syncedBookCount: Int { LibriVoxSyncCheckpoint.standard.syncedBookCount }
    static var isLocalSearchReady: Bool { LibriVoxSyncCheckpoint.standard.isLocalSearchReady }

    static var isSyncDue: Bool {
        let checkpoint = LibriVoxSyncCheckpoint.standard
        return syncIsDue(
            isLocalSearchReady: checkpoint.isLocalSearchReady,
            lastSyncDate: checkpoint.lastSyncDate,
            now: .now
        )
    }

    static func syncIsDue(
        isLocalSearchReady: Bool,
        lastSyncDate: Date?,
        now: Date
    ) -> Bool {
        guard isLocalSearchReady, let lastSyncDate else { return true }
        return now.timeIntervalSince(lastSyncDate) >= 86_400
    }

    /// Runs a full sync (resuming from the persisted cursor) if the catalog has never
    /// completed, or an incremental sync if the last one is more than 24 hours old.
    /// All SwiftData work happens on `store`; nothing here touches the main actor except
    /// the `onProgress` hop.
    static func syncIfNeeded(
        store: LibriVoxCatalogStore,
        checkpoint: LibriVoxSyncCheckpoint = .standard,
        feed: LibriVoxCatalogFeed = .live,
        pauseFlag: LibriVoxSyncPauseFlag = LibriVoxSyncPauseFlag(),
        now: Date = .now,
        onProgress: @escaping @MainActor @Sendable (LibriVoxSyncProgress) -> Void
    ) async throws -> LibriVoxSyncOutcome {
        if let last = checkpoint.lastSyncDate, checkpoint.genresBackfillDone {
            guard now.timeIntervalSince(last) >= 86_400 else { return .skipped }
            return try await incrementalSync(
                since: last, store: store, checkpoint: checkpoint, feed: feed,
                pauseFlag: pauseFlag, onProgress: onProgress
            )
        }
        return try await fullSync(
            store: store, checkpoint: checkpoint, feed: feed,
            pauseFlag: pauseFlag, onProgress: onProgress
        )
    }

    /// Upserts a small set of pre-fetched API books into the store and saves.
    /// Used by the featured-classics preload and detail refreshes so curated rows exist
    /// before the full catalog sync runs. A later full sync matches these rows by `id`.
    @MainActor
    static func seed(_ apiBooks: [LibriVoxAPIBook], into context: ModelContext) throws {
        guard !apiBooks.isEmpty else { return }
        let ids = apiBooks.map(\.id)
        let existing = try context.fetch(FetchDescriptor(predicate: #Predicate<LibriVoxBook> { ids.contains($0.id) }))
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for apiBook in apiBooks {
            if let book = byID[apiBook.id] {
                apply(apiBook, to: book)
            } else {
                let book = makeBook(from: apiBook)
                context.insert(book)
                byID[apiBook.id] = book
            }
        }
        try context.save()
    }

    // MARK: - Private

    private static func fullSync(
        store: LibriVoxCatalogStore,
        checkpoint: LibriVoxSyncCheckpoint,
        feed: LibriVoxCatalogFeed,
        pauseFlag: LibriVoxSyncPauseFlag,
        onProgress: @escaping @MainActor @Sendable (LibriVoxSyncProgress) -> Void
    ) async throws -> LibriVoxSyncOutcome {
        var offset = checkpoint.resumeOffset
        var processed = 0

        while true {
            if pauseFlag.isRaised { return .paused }
            let page = try await fetchPageWithRetry(attempts: 3) { try await feed.fullPage(offset) }
            guard !page.isEmpty else { break }

            // Commit the page even if a pause arrived while it downloaded — finishing the
            // current page is the point of the background grace period.
            let saved = try await store.upsert(page)
            processed += page.count
            offset += page.count
            checkpoint.recordPage(nextOffset: offset, savedCount: saved)
            await onProgress(LibriVoxSyncProgress(savedCount: saved, processedThisRun: processed))

            if page.count < pageSize { break }
            if pauseFlag.isRaised { return .paused }
            try Task.checkCancellation()
        }

        let total = try await store.count()
        checkpoint.markFullPassComplete(total: total)
        return .completed(processed: processed)
    }

    private static func incrementalSync(
        since: Date,
        store: LibriVoxCatalogStore,
        checkpoint: LibriVoxSyncCheckpoint,
        feed: LibriVoxCatalogFeed,
        pauseFlag: LibriVoxSyncPauseFlag,
        onProgress: @escaping @MainActor @Sendable (LibriVoxSyncProgress) -> Void
    ) async throws -> LibriVoxSyncOutcome {
        var offset = 0
        var processed = 0
        var saved: Int?
        while true {
            if pauseFlag.isRaised { return .paused }
            let page = try await fetchPageWithRetry(attempts: 3) { try await feed.sincePage(since, offset) }
            guard !page.isEmpty else { break }
            let count = try await store.upsert(page)
            saved = count
            checkpoint.recordSavedCount(count)
            processed += page.count
            offset += page.count
            await onProgress(LibriVoxSyncProgress(savedCount: count, processedThisRun: processed))
            if page.count < pageSize { break }
            try Task.checkCancellation()
        }
        // An interrupted incremental pass re-runs from `since` next time — the window is
        // small and upserts are idempotent, so no cursor is needed here.
        checkpoint.markIncrementalComplete(total: saved)
        return .completed(processed: processed)
    }

    /// Fetches one catalog page, retrying briefly on a transient failure so a single flaky
    /// response from the LibriVox feed doesn't abort the whole multi-thousand-book sync.
    /// Cancellation and offline conditions are not retried — they propagate immediately.
    static func fetchPageWithRetry(
        attempts: Int,
        _ fetch: () async throws -> [LibriVoxAPIBook]
    ) async throws -> [LibriVoxAPIBook] {
        var lastError: Error?
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            do {
                return try await fetch()
            } catch let urlError as URLError where urlError.code == .notConnectedToInternet
                || urlError.code == .cancelled {
                throw urlError // offline or cancelled — no point retrying
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                // Linear backoff: 0.5s, 1.0s — short enough to stay responsive. No sleep after
                // the final attempt so the error surfaces immediately.
                if attempt < attempts - 1 {
                    try await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
                }
            }
        }
        throw lastError ?? LibriVoxAPIError.unreadableResponse
    }

    static func apply(_ apiBook: LibriVoxAPIBook, to book: LibriVoxBook) {
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
    }

    static func makeBook(from apiBook: LibriVoxAPIBook) -> LibriVoxBook {
        LibriVoxBook(
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
        )
    }
}

// MARK: - Local catalog query

/// The browse screen's search + filter state, as a value the store can evaluate.
nonisolated struct LibriVoxCatalogQuery: Sendable, Equatable {
    var text: String = ""
    var language: String?
    var genre: String?
    var duration: DurationFilter?

    var hasText: Bool { !text.isEmpty }

    /// The same narrowing applied to remote (API) results so live and cached results
    /// obey identical filters.
    func matches(language bookLanguage: String, genres: [String], totalTimeSecs: Int) -> Bool {
        if let language, bookLanguage != language { return false }
        if let genre, !genres.contains(genre) { return false }
        if let duration, !duration.matches(seconds: totalTimeSecs) { return false }
        return true
    }

    func matches(_ apiBook: LibriVoxAPIBook) -> Bool {
        matches(language: apiBook.language, genres: apiBook.genreNames, totalTimeSecs: apiBook.totalTimeSecs)
    }

    static func rank(title: String, author: String, query: String) -> Int {
        let t = title.lowercased()
        if t.hasPrefix(query) { return 0 }
        if t.contains(query) { return 1 }
        if author.lowercased().contains(query) { return 2 }
        return 3
    }
}

nonisolated struct LibriVoxFilterOptions: Sendable, Equatable {
    var languages: [String]
    var genres: [String]
}

// MARK: - Background store

/// Owns a background `ModelContext` for every catalog-sized operation: page upserts,
/// filter-option aggregation, and local search. Callers get back plain values (ids,
/// counts, strings) and resolve the few rows they display on their own context.
@ModelActor
actor LibriVoxCatalogStore {
    /// Creates the store off the main thread. A `@ModelActor` built on the main thread
    /// gets a main-queue context, which would put every page save back on the main actor.
    static func make(container: ModelContainer) async -> LibriVoxCatalogStore {
        await Task.detached(priority: .utility) {
            LibriVoxCatalogStore(modelContainer: container)
        }.value
    }

    /// Inserts or refreshes one page and saves. Returns the stored row count.
    @discardableResult
    func upsert(_ page: [LibriVoxAPIBook]) throws -> Int {
        guard !page.isEmpty else { return try count() }
        let ids = page.map(\.id)
        let existing = try modelContext.fetch(
            FetchDescriptor(predicate: #Predicate<LibriVoxBook> { ids.contains($0.id) })
        )
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for apiBook in page {
            if let book = byID[apiBook.id] {
                LibriVoxCatalogSync.apply(apiBook, to: book)
            } else {
                let book = LibriVoxCatalogSync.makeBook(from: apiBook)
                modelContext.insert(book)
                byID[apiBook.id] = book
            }
        }
        try modelContext.save()
        return try count()
    }

    func count() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<LibriVoxBook>())
    }

    /// Languages (English first, then alphabetical) and genres (most common first).
    func filterOptions() throws -> LibriVoxFilterOptions {
        var languages = Set<String>()
        var genreCounts: [String: Int] = [:]
        try modelContext.enumerate(FetchDescriptor<LibriVoxBook>(), batchSize: 1_000) { book in
            if !book.language.isEmpty { languages.insert(book.language) }
            for genre in book.genres { genreCounts[genre, default: 0] += 1 }
        }
        var sortedLanguages = languages.sorted()
        if let index = sortedLanguages.firstIndex(of: "English") {
            sortedLanguages.remove(at: index)
            sortedLanguages.insert("English", at: 0)
        }
        let genres = genreCounts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }.map(\.key)
        return LibriVoxFilterOptions(languages: sortedLanguages, genres: genres)
    }

    /// The first cached book whose title contains each candidate, in candidate order,
    /// deduplicated, up to `limit`.
    func firstIDs(matchingTitles titles: [String], limit: Int) throws -> [String] {
        var ids: [String] = []
        for title in titles where ids.count < limit {
            var descriptor = FetchDescriptor(predicate: #Predicate<LibriVoxBook> {
                $0.title.localizedStandardContains(title)
            })
            descriptor.fetchLimit = 1
            if let id = try modelContext.fetch(descriptor).first?.id, !ids.contains(id) {
                ids.append(id)
            }
        }
        return ids
    }

    /// Ordered ids of locally cached books matching `query`.
    func search(_ query: LibriVoxCatalogQuery, limit: Int = 500) throws -> [String] {
        let text = query.text
        var descriptor: FetchDescriptor<LibriVoxBook>
        if query.hasText, let language = query.language {
            descriptor = FetchDescriptor(predicate: #Predicate<LibriVoxBook> { book in
                (book.title.localizedStandardContains(text) ||
                 book.authorDisplay.localizedStandardContains(text) ||
                 book.bookDescription.localizedStandardContains(text)) &&
                book.language == language
            })
        } else if query.hasText {
            descriptor = FetchDescriptor(predicate: #Predicate<LibriVoxBook> { book in
                book.title.localizedStandardContains(text) ||
                book.authorDisplay.localizedStandardContains(text) ||
                book.bookDescription.localizedStandardContains(text)
            })
        } else if let language = query.language {
            descriptor = FetchDescriptor(predicate: #Predicate<LibriVoxBook> { $0.language == language })
        } else {
            descriptor = FetchDescriptor<LibriVoxBook>()
        }
        if !query.hasText { descriptor.sortBy = [SortDescriptor(\.title)] }

        // Genre (JSON-encoded) and duration buckets can't go into the predicate; filter here,
        // off the main actor, and stop once enough matches are found.
        let needle = text.lowercased()
        var matches: [(id: String, rank: Int, title: String)] = []
        try modelContext.enumerate(descriptor, batchSize: 1_000) { book in
            guard query.matches(language: book.language, genres: book.genres,
                                totalTimeSecs: book.totalTimeSecs) else { return }
            let rank = query.hasText
                ? LibriVoxCatalogQuery.rank(title: book.title, author: book.authorDisplay, query: needle)
                : 0
            matches.append((book.id, rank, book.title))
        }
        if query.hasText {
            matches.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.title < $1.title }
        }
        return matches.prefix(limit).map(\.id)
    }
}
