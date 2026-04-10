//
//  LibriVoxAPIClient.swift
//  Pageless
//

import Foundation

// MARK: - Genre model

struct LibriVoxAPIGenre: Decodable {
    let id: String
    let name: String

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)).map(String.init)
            ?? ((try? c.decode(String.self, forKey: .id)) ?? "")
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
    }

    enum CodingKeys: String, CodingKey { case id, name }
}

// MARK: - Response envelopes

private struct CatalogResponse: Decodable {
    let books: [LibriVoxAPIBook]?
}

private struct TracksResponse: Decodable {
    let sections: [LibriVoxAPITrack]?
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

    /// Fetches all books updated since the given timestamp, paginating until exhausted.
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

    /// Fetches all tracks for a LibriVox project ID.
    static func fetchTracks(projectID: String) async throws -> [LibriVoxAPITrack] {
        var components = URLComponents(string: "\(baseURL)/audiotracks")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "project_id", value: projectID),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TracksResponse.self, from: data)
        return (response.sections ?? []).sorted { $0.sectionNumber < $1.sectionNumber }
    }

    // MARK: - Private

    private static func fetchBooks(queryItems: [URLQueryItem]) async throws -> [LibriVoxAPIBook] {
        var components = URLComponents(string: "\(baseURL)/audiobooks")!
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(CatalogResponse.self, from: data)
        return response.books ?? []
    }
}
