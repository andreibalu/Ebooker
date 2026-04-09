//
//  FreeBookCatalogService.swift
//  Pageless
//

import Foundation

@MainActor
enum FreeBookCatalogService {

    // MARK: - Static Seeds

    struct BookSeed {
        let id: String
        let archiveIdentifier: String
        let title: String
        let author: String
        let description: String
        let estimatedSizeMB: Double
    }

    static let bookSeeds: [BookSeed] = [
        BookSeed(
            id: "librivox-christmas-carol",
            archiveIdentifier: "christmas_carol_1212_librivox",
            title: "A Christmas Carol",
            author: "Charles Dickens",
            description: "Ebenezer Scrooge, a miserly old man, is visited by the ghosts of Christmas Past, Present, and Yet to Come, who show him the error of his ways and inspire a remarkable transformation.",
            estimatedSizeMB: 87
        ),
        BookSeed(
            id: "librivox-alice-wonderland",
            archiveIdentifier: "alices_adventures_1003",
            title: "Alice's Adventures in Wonderland",
            author: "Lewis Carroll",
            description: "A young girl named Alice follows a White Rabbit down a rabbit hole into a surreal underground world filled with peculiar creatures and nonsensical adventures.",
            estimatedSizeMB: 75
        ),
        BookSeed(
            id: "librivox-frankenstein",
            archiveIdentifier: "frankenstein_cs_librivox",
            title: "Frankenstein",
            author: "Mary Shelley",
            description: "Victor Frankenstein, a young scientist, creates a sapient creature in an unorthodox experiment. This haunting novel explores themes of ambition, isolation, and the consequences of playing God.",
            estimatedSizeMB: 220
        ),
        BookSeed(
            id: "librivox-metamorphosis",
            archiveIdentifier: "metamorphosis_librivox",
            title: "The Metamorphosis",
            author: "Franz Kafka",
            description: "Gregor Samsa wakes one morning to find himself transformed into a monstrous insect. This haunting novella explores alienation, guilt, and the absurdity of modern existence.",
            estimatedSizeMB: 74
        ),
        BookSeed(
            id: "librivox-picture-dorian-gray",
            archiveIdentifier: "picture_dorian_gray_1204_librivox",
            title: "The Picture of Dorian Gray",
            author: "Oscar Wilde",
            description: "A young man's portrait ages while he remains youthful, descending into a life of corruption and sin. Wilde's only novel is a masterful exploration of beauty, morality, and the price of vanity.",
            estimatedSizeMB: 261
        )
    ]

    // MARK: - Cache

    private static var cache: [FreeBookCatalogEntry]?

    // MARK: - Public API

    static func allEntries(session: URLSession = .shared) async -> [FreeBookCatalogEntry] {
        if let cache { return cache }

        var entries: [FreeBookCatalogEntry] = []
        await withTaskGroup(of: FreeBookCatalogEntry?.self) { group in
            for seed in bookSeeds {
                group.addTask { try? await fetchEntry(for: seed, session: session) }
            }
            for await entry in group {
                if let entry { entries.append(entry) }
            }
        }

        // Restore original order from seeds
        let orderedIds = bookSeeds.map(\.id)
        entries.sort {
            (orderedIds.firstIndex(of: $0.id) ?? Int.max) <
            (orderedIds.firstIndex(of: $1.id) ?? Int.max)
        }

        if !entries.isEmpty { cache = entries }
        return entries
    }

    static func availableEntries(excluding downloadedIds: Set<String>, session: URLSession = .shared) async -> [FreeBookCatalogEntry] {
        await allEntries(session: session).filter { !downloadedIds.contains($0.id) }
    }

    static func resetCache() {
        cache = nil
    }

    // MARK: - Fetch

    private static func fetchEntry(for seed: BookSeed, session: URLSession) async throws -> FreeBookCatalogEntry {
        guard let url = URL(string: "https://archive.org/metadata/\(seed.archiveIdentifier)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let metadata = try JSONDecoder().decode(ArchiveMetadataResponse.self, from: data)

        let audioFiles = metadata.files
            .filter { $0.format == "64Kbps MP3" && $0.name.hasSuffix(".mp3") }
            .sorted {
                let ta = $0.resolvedTrackNumber ?? Int.max
                let tb = $1.resolvedTrackNumber ?? Int.max
                return ta != tb ? ta < tb : $0.name < $1.name
            }

        guard !audioFiles.isEmpty else { throw URLError(.cannotParseResponse) }

        let tracks = audioFiles.enumerated().map { index, file -> FreeBookTrackEntry in
            let duration = Double(file.length ?? "") ?? 0
            let downloadURL = "https://archive.org/download/\(seed.archiveIdentifier)/\(file.name)"
            let title = (file.title?.isEmpty == false) ? file.title! : "Track \(index + 1)"
            return FreeBookTrackEntry(
                id: "\(seed.id)-\(index + 1)",
                title: title,
                fileName: file.name,
                downloadURL: downloadURL,
                durationSeconds: duration,
                orderIndex: index
            )
        }

        let totalDuration = tracks.reduce(0) { $0 + $1.durationSeconds }
        let totalBytes = audioFiles.compactMap { Int64($0.size ?? "") }.reduce(0, +)
        let sizeMB = totalBytes > 0 ? Double(totalBytes) / 1_048_576 : seed.estimatedSizeMB

        return FreeBookCatalogEntry(
            id: seed.id,
            title: seed.title,
            author: seed.author,
            description: seed.description,
            coverAssetName: nil,
            totalDurationSeconds: totalDuration,
            downloadSizeMB: sizeMB,
            tracks: tracks
        )
    }
}

// MARK: - archive.org Metadata API Models

private struct ArchiveMetadataResponse: Decodable {
    let files: [ArchiveFile]

    struct ArchiveFile: Decodable {
        let name: String
        let format: String?
        let length: String?
        let title: String?
        let track: String?
        let size: String?

        var resolvedTrackNumber: Int? {
            guard let track else { return nil }
            return Int(track.trimmingCharacters(in: .whitespaces))
        }
    }
}
