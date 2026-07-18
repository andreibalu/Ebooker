//
//  LibriVoxAPIClient.swift
//  Pageless
//

import Foundation

// MARK: - Genre model

struct LibriVoxAPIGenre: Decodable {
    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)).map(String.init)
            ?? ((try? c.decode(String.self, forKey: .id)) ?? "")
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
    }

    enum CodingKeys: String, CodingKey { case id, name }
}

// MARK: - Errors

/// Typed, user-presentable failures from the LibriVox feed API.
///
/// The point of this type is to never let a raw `DecodingError` ("The data couldn't be
/// read because it isn't in the correct format.") reach the UI. LibriVox routinely returns
/// non-`books`/`sections` payloads — an `{"error": "..."}` body with HTTP 200 when a query
/// matches nothing, or an HTML maintenance page on server hiccups — and the strict decoders
/// below would otherwise surface that confusing message. `URLError` is intentionally NOT
/// wrapped here so the view model's offline classification still works.
enum LibriVoxAPIError: LocalizedError {
    case serverUnavailable(status: Int)
    case unreadableResponse

    var errorDescription: String? {
        switch self {
        case .serverUnavailable:
            "LibriVox is temporarily unavailable. Please try again in a moment."
        case .unreadableResponse:
            "LibriVox returned an unexpected response. Please try again in a moment."
        }
    }
}

// MARK: - Response envelopes

private struct CatalogResponse: Decodable {
    let books: [LibriVoxAPIBook]?
}

private struct TracksResponse: Decodable {
    let sections: [LibriVoxAPITrack]?
}

/// LibriVox returns this shape (with HTTP 200) when a query matches nothing, e.g.
/// `{"error": "Audiobooks could not be found"}`. Treated as an empty result, not a failure.
private struct LibriVoxErrorEnvelope: Decodable {
    let error: String
}

// MARK: - API models

struct LibriVoxAPIBook: Decodable {
    let id: String
    let title: String
    let description: String
    let totalTimeSecs: Int
    let authors: [LibriVoxAPIAuthor]?
    let language: String
    let urlLibrivox: String?
    let urlIarchive: String?
    let urlRss: String?
    let coverartThumbnail: String?
    let genres: [LibriVoxAPIGenre]?

    var authorDisplay: String {
        guard let authors, !authors.isEmpty else { return "Unknown Author" }
        let names = authors.map(\.displayName).filter { !$0.isEmpty }
        return names.isEmpty ? "Unknown Author" : names.joined(separator: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, language, authors
        case totalTimeSecs = "totaltimesecs"
        case urlLibrivox = "url_librivox"
        case urlIarchive = "url_iarchive"
        case urlRss = "url_rss"
        case coverartThumbnail = "coverart_thumbnail"
        case genres
    }

    var genreNames: [String] {
        (genres ?? []).map(\.name).filter { !$0.isEmpty }
    }

    init(
        id: String,
        title: String,
        description: String,
        totalTimeSecs: Int,
        authors: [LibriVoxAPIAuthor]?,
        language: String,
        urlLibrivox: String?,
        urlIarchive: String?,
        urlRss: String?,
        coverartThumbnail: String?,
        genres: [LibriVoxAPIGenre]?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.totalTimeSecs = totalTimeSecs
        self.authors = authors
        self.language = language
        self.urlLibrivox = urlLibrivox
        self.urlIarchive = urlIarchive
        self.urlRss = urlRss
        self.coverartThumbnail = coverartThumbnail
        self.genres = genres
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id arrives as Int in the API but we store it as String
        if let intVal = try? c.decode(Int.self, forKey: .id) {
            id = String(intVal)
        } else {
            id = (try? c.decode(String.self, forKey: .id)) ?? ""
        }
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        totalTimeSecs = (try? c.decode(Int.self, forKey: .totalTimeSecs)) ?? 0
        authors = try? c.decode([LibriVoxAPIAuthor].self, forKey: .authors)
        language = (try? c.decode(String.self, forKey: .language)) ?? ""
        urlLibrivox = try? c.decode(String.self, forKey: .urlLibrivox)
        urlIarchive = try? c.decode(String.self, forKey: .urlIarchive)
        urlRss = try? c.decode(String.self, forKey: .urlRss)
        coverartThumbnail = try? c.decode(String.self, forKey: .coverartThumbnail)
        genres = try? c.decode([LibriVoxAPIGenre].self, forKey: .genres)
    }
}

struct LibriVoxAPIAuthor: Decodable {
    let firstName: String?
    let lastName: String?

    init(firstName: String?, lastName: String?) {
        self.firstName = firstName
        self.lastName = lastName
    }

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
    }

    var displayName: String {
        [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct LibriVoxAPITrack: Decodable {
    let id: String
    let sectionNumber: Int
    let title: String
    let playtime: String
    let listenURL: String

    enum CodingKeys: String, CodingKey {
        case id, title, playtime
        case sectionNumber = "section_number"
        case listenURL = "listen_url"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intVal = try? c.decode(Int.self, forKey: .id) {
            id = String(intVal)
        } else {
            id = (try? c.decode(String.self, forKey: .id)) ?? ""
        }
        if let intSection = try? c.decode(Int.self, forKey: .sectionNumber) {
            sectionNumber = intSection
        } else if let strSection = try? c.decode(String.self, forKey: .sectionNumber) {
            sectionNumber = Int(strSection) ?? 0
        } else {
            sectionNumber = 0
        }
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        playtime = (try? c.decode(String.self, forKey: .playtime)) ?? "0:00"
        listenURL = (try? c.decode(String.self, forKey: .listenURL)) ?? ""
    }

    /// Duration in seconds parsed from "HH:MM:SS" or "MM:SS" playtime string.
    var durationSeconds: Double {
        let parts = playtime.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        case 1: return parts[0]
        default: return 0
        }
    }
}

// MARK: - Client

enum LibriVoxAPIClient {
    private static let baseURL = "https://librivox.org/api/feed"

    private static let catalogFields: [URLQueryItem] = [
        // The feed silently omits `genres` from responses unless extended=1 is set,
        // even when explicitly requested via fields[]. fields[] still limits the
        // payload, so this does not pull in the heavy `sections` array.
        URLQueryItem(name: "extended", value: "1"),
        URLQueryItem(name: "fields[]", value: "id"),
        URLQueryItem(name: "fields[]", value: "title"),
        URLQueryItem(name: "fields[]", value: "description"),
        URLQueryItem(name: "fields[]", value: "totaltimesecs"),
        URLQueryItem(name: "fields[]", value: "authors"),
        URLQueryItem(name: "fields[]", value: "language"),
        URLQueryItem(name: "fields[]", value: "url_librivox"),
        URLQueryItem(name: "fields[]", value: "url_iarchive"),
        URLQueryItem(name: "fields[]", value: "url_rss"),
        URLQueryItem(name: "fields[]", value: "coverart_thumbnail"),
        URLQueryItem(name: "fields[]", value: "genres"),
    ]

    /// Fetches a single page of the catalog at the given offset.
    static func fetchCatalogPage(offset: Int) async throws -> [LibriVoxAPIBook] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "offset", value: "\(offset)"),
        ]
        items.append(contentsOf: catalogFields)
        return try await fetchBooks(queryItems: items)
    }

    /// Fetches books newly cataloged since the timestamp, paginating until exhausted.
    static func fetchCatalogSince(timestamp: Date) async throws -> [LibriVoxAPIBook] {
        let unix = Int(timestamp.timeIntervalSince1970)
        var allBooks: [LibriVoxAPIBook] = []
        var offset = 0
        while true {
            var items: [URLQueryItem] = [
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "offset", value: "\(offset)"),
                URLQueryItem(name: "since", value: "\(unix)"),
            ]
            items.append(contentsOf: catalogFields)
            let page = try await fetchBooks(queryItems: items)
            guard !page.isEmpty else { break }
            allBooks.append(contentsOf: page)
            if page.count < 50 { break }
            offset += page.count
        }
        return allBooks
    }

    /// Searches LibriVox's feed by title and author concurrently. The feed exposes
    /// those as separate parameters, so results are merged locally and deduplicated.
    static func searchBooks(query: String, limit: Int = 50) async throws -> [LibriVoxAPIBook] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        async let titleMatches = fetchSearchResults(parameter: "title", query: trimmed, limit: limit)
        async let authorMatches = fetchSearchResults(parameter: "author", query: trimmed, limit: limit)
        return rankAndMergeSearchResults(
            titleMatches: try await titleMatches,
            authorMatches: try await authorMatches,
            query: trimmed
        )
    }

    static func rankAndMergeSearchResults(
        titleMatches: [LibriVoxAPIBook],
        authorMatches: [LibriVoxAPIBook],
        query: String
    ) -> [LibriVoxAPIBook] {
        let byID = Dictionary(
            (titleMatches + authorMatches).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return byID.values.sorted { lhs, rhs in
            let lhsScore = remoteSearchRank(lhs, query: needle)
            let rhsScore = remoteSearchRank(rhs, query: needle)
            if lhsScore != rhsScore { return lhsScore < rhsScore }
            let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    /// Fetches catalog metadata for a specific set of LibriVox project IDs.
    ///
    /// The LibriVox feed API does not reliably support fetching multiple IDs in a
    /// single request, so each ID is fetched individually (concurrently). Failures
    /// for individual IDs are skipped rather than failing the whole batch — the
    /// caller degrades gracefully when the network is unavailable.
    static func fetchBooks(ids: [String]) async throws -> [LibriVoxAPIBook] {
        guard !ids.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: LibriVoxAPIBook?.self) { group in
            for id in ids {
                group.addTask { try? await fetchBook(id: id) }
            }
            var books: [LibriVoxAPIBook] = []
            for try await book in group {
                if let book { books.append(book) }
            }
            return books
        }
    }

    /// Fetches catalog metadata for a single LibriVox project ID.
    static func fetchBook(id: String) async throws -> LibriVoxAPIBook? {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "id", value: id),
        ]
        items.append(contentsOf: catalogFields)
        return try await fetchBooks(queryItems: items).first
    }

    private static func fetchSearchResults(
        parameter: String,
        query: String,
        limit: Int
    ) async throws -> [LibriVoxAPIBook] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: parameter, value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "0"),
        ]
        items.append(contentsOf: catalogFields)
        return try await fetchBooks(queryItems: items)
    }

    private static func remoteSearchRank(_ book: LibriVoxAPIBook, query: String) -> Int {
        let title = book.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let author = book.authorDisplay.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if title.hasPrefix(query) { return 0 }
        if title.contains(query) { return 1 }
        if author.contains(query) { return 2 }
        return 3
    }

    /// Fetches all tracks for a LibriVox project ID.
    static func fetchTracks(projectID: String) async throws -> [LibriVoxAPITrack] {
        var components = URLComponents(string: "\(baseURL)/audiotracks")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "project_id", value: projectID),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let data = try await fetchData(from: url)
        let sections = try decode(data) { (r: TracksResponse) in r.sections }
        return sections.sorted { $0.sectionNumber < $1.sectionNumber }
    }

    // MARK: - Private

    private static func fetchBooks(queryItems: [URLQueryItem]) async throws -> [LibriVoxAPIBook] {
        var components = URLComponents(string: "\(baseURL)/audiobooks")!
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }
        let data = try await fetchData(from: url)
        return try decode(data) { (r: CatalogResponse) in r.books }
    }

    /// Performs the request and validates the HTTP status. `URLError`s (offline, timeout,
    /// DNS) propagate untouched so callers can classify connectivity problems; any non-2xx
    /// status becomes a friendly `LibriVoxAPIError.serverUnavailable`.
    private static func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LibriVoxAPIError.serverUnavailable(status: http.statusCode)
        }
        return data
    }

    /// Lenient decode that tolerates the three things LibriVox actually returns:
    ///   1. The expected envelope → its elements (or `[]` if the array key is absent/null).
    ///   2. An `{"error": "..."}` body (HTTP 200, no match) → `[]`, a normal empty result.
    ///   3. Anything else — an HTML maintenance page, a truncated body → `unreadableResponse`,
    ///      a friendly retriable error instead of a raw `DecodingError`.
    private static func decode<Envelope: Decodable, Element>(
        _ data: Data,
        _ extract: (Envelope) -> [Element]?
    ) throws -> [Element] where Element: Decodable {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            return extract(envelope) ?? []
        }
        // Optional array keys mean the envelope usually decodes even for the no-results body,
        // but if the shape differs this still catches the explicit error sentinel.
        if (try? decoder.decode(LibriVoxErrorEnvelope.self, from: data)) != nil {
            return []
        }
        throw LibriVoxAPIError.unreadableResponse
    }
}

@MainActor
protocol LibriVoxRemoteSearching {
    func search(query: String) async throws -> [LibriVoxAPIBook]
    func fetchBook(id: String) async throws -> LibriVoxAPIBook?
}

struct LiveLibriVoxRemoteSearch: LibriVoxRemoteSearching {
    func search(query: String) async throws -> [LibriVoxAPIBook] {
        try await LibriVoxAPIClient.searchBooks(query: query)
    }

    func fetchBook(id: String) async throws -> LibriVoxAPIBook? {
        try await LibriVoxAPIClient.fetchBook(id: id)
    }
}
