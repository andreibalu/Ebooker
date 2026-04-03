//
//  PlayAudiobookIntent.swift
//  Pageless
//

import AppIntents
import Foundation

struct AudiobookEntity: AppEntity {
    static var defaultQuery = AudiobookEntityQuery()
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Audiobook"

    var id: String
    var title: String
    var author: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(author)")
    }
}

struct AudiobookEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [AudiobookEntity] {
        SharedDefaults.loadLibrary()
            .filter { $0.title.localizedCaseInsensitiveContains(string) }
            .map { AudiobookEntity(id: $0.id, title: $0.title, author: $0.author) }
    }

    func entities(for identifiers: [String]) async throws -> [AudiobookEntity] {
        let library = SharedDefaults.loadLibrary()
        return identifiers.compactMap { id in
            library.first { $0.id == id }.map {
                AudiobookEntity(id: $0.id, title: $0.title, author: $0.author)
            }
        }
    }

    func suggestedEntities() async throws -> [AudiobookEntity] {
        SharedDefaults.loadLibrary()
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
            .prefix(5)
            .map { AudiobookEntity(id: $0.id, title: $0.title, author: $0.author) }
    }
}

struct PlayAudiobookIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Audiobook"
    static var description = IntentDescription("Resumes playback of an audiobook in Pageless.")
    static var openAppWhenRun = true

    @Parameter(title: "Audiobook")
    var audiobook: AudiobookEntity

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct ResumePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Playback"
    static var description = IntentDescription("Resumes the last audiobook you were listening to.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct PausePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Playback"
    static var description = IntentDescription("Pauses the currently playing audiobook.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct OpenLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Library"
    static var description = IntentDescription("Opens your audiobook library in Pageless.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
