//
//  LibraryImportService.swift
//  Pageless
//

import AVFoundation
import Foundation
import SwiftData

struct PendingImportSelection: Identifiable {
    let id = UUID()
    let sourceURLs: [URL]
    let suggestedTitle: String
    let suggestedAuthor: String
    let coverArtData: Data?
    let tracks: [TrackImportPreview]

    var totalDuration: Double {
        tracks.reduce(0) { $0 + $1.duration }
    }
}

struct TrackImportPreview: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let title: String
    let originalFileName: String
    let duration: Double
}

enum LibraryImportError: LocalizedError {
    case noAudioFiles
    case couldNotReadFile(URL)
    case couldNotCreateStorage
    case invalidTitle

    var errorDescription: String? {
        switch self {
        case .noAudioFiles:
            "Choose at least one audio file to create an audiobook."
        case .couldNotReadFile(let url):
            "The file \(url.lastPathComponent) could not be accessed."
        case .couldNotCreateStorage:
            "The app could not create local storage for this audiobook."
        case .invalidTitle:
            "Give the audiobook a title before importing it."
        }
    }
}

enum LibraryImportService {
    static func prepareImport(from urls: [URL]) async throws -> PendingImportSelection {
        let audioURLs = urls
            .filter { !$0.hasDirectoryPath }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard !audioURLs.isEmpty else {
            throw LibraryImportError.noAudioFiles
        }

        var previews: [TrackImportPreview] = []

        for url in audioURLs {
            let duration = try await measureDuration(for: url)
            previews.append(
                TrackImportPreview(
                    sourceURL: url,
                    title: url.deletingPathExtension().lastPathComponent,
                    originalFileName: url.lastPathComponent,
                    duration: duration
                )
            )
        }

        return PendingImportSelection(
            sourceURLs: audioURLs,
            suggestedTitle: titleSuggestion(for: audioURLs),
            suggestedAuthor: "",
            coverArtData: nil,
            tracks: previews
        )
    }

    @discardableResult
    static func importAudiobook(
        from pending: PendingImportSelection,
        title: String,
        author: String,
        modelContext: ModelContext
    ) throws -> Audiobook {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw LibraryImportError.invalidTitle
        }

        let folderName = UUID().uuidString
        let folderURL = try storageFolderURL(for: folderName)

        let audiobook = Audiobook(
            title: trimmedTitle,
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            folderName: folderName,
            coverArtData: pending.coverArtData,
            totalDuration: pending.totalDuration
        )

        modelContext.insert(audiobook)

        for (index, track) in pending.tracks.enumerated() {
            let storedFileName = "\(String(format: "%03d", index + 1))-\(sanitizedFileName(from: track.originalFileName))"
            let destinationURL = folderURL.appendingPathComponent(storedFileName, conformingTo: .audio)

            try copyFile(from: track.sourceURL, to: destinationURL)

            let savedTrack = AudioTrack(
                title: track.title,
                originalFileName: track.originalFileName,
                storedFileName: storedFileName,
                orderIndex: index,
                duration: track.duration,
                audiobook: audiobook
            )

            audiobook.tracks.append(savedTrack)
            modelContext.insert(savedTrack)
        }

        audiobook.totalDuration = audiobook.sortedTracks.reduce(0) { $0 + $1.duration }
        try modelContext.save()

        return audiobook
    }

    static func deleteAudiobook(
        _ audiobook: Audiobook,
        deleteFiles: Bool,
        modelContext: ModelContext
    ) throws {
        if deleteFiles {
            let folderURL = try storageFolderURL(for: audiobook.folderName)
            if FileManager.default.fileExists(atPath: folderURL.path()) {
                try FileManager.default.removeItem(at: folderURL)
            }
        }

        modelContext.delete(audiobook)
        try modelContext.save()
    }

    static func fileURL(for track: AudioTrack, in audiobook: Audiobook) throws -> URL {
        try storageFolderURL(for: audiobook.folderName).appendingPathComponent(track.storedFileName)
    }

    private static func titleSuggestion(for urls: [URL]) -> String {
        guard let firstURL = urls.first else { return "Imported Audiobook" }

        if urls.count == 1 {
            return firstURL.deletingPathExtension().lastPathComponent
        }

        let parentDirectories = Set(urls.map { $0.deletingLastPathComponent().lastPathComponent })
        if parentDirectories.count == 1, let directoryName = parentDirectories.first, !directoryName.isEmpty {
            return directoryName
        }

        return firstURL.deletingPathExtension().lastPathComponent
    }

    private static func measureDuration(for url: URL) async throws -> Double {
        try await withSecurityScopedAccess(to: url) {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            return max(duration.seconds, 0)
        }
    }

    private static func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        try withSecurityScopedAccess(to: sourceURL) {
            if FileManager.default.fileExists(atPath: destinationURL.path()) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func storageFolderURL(for folderName: String) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let libraryURL = applicationSupport.appendingPathComponent("Audiobooks", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)

        let audiobookFolderURL = libraryURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: audiobookFolderURL, withIntermediateDirectories: true)
        return audiobookFolderURL
    }

    private static func sanitizedFileName(from name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "_")

        return sanitized.isEmpty ? UUID().uuidString : sanitized
    }

    private static func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () throws -> T
    ) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try operation()
    }

    private static func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () async throws -> T
    ) async throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try await operation()
    }
}
