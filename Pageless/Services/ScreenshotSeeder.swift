//
//  ScreenshotSeeder.swift
//  Pageless
//
//  DEBUG-only seeder for App Store screenshot capture. Populates the library with a handful of
//  public-domain titles (generated silent audio — no real audiobook content is bundled or
//  distributed) and a few moments hand-written from Pride and Prejudice.
//
//  Only runs when UITEST_SEED_SCREENSHOTS=1 is set in the launch environment, so a normal
//  developer debug build never touches this path. Compiled out of Release entirely.
//

#if DEBUG
import AVFoundation
import Foundation
import SwiftData

enum ScreenshotSeeder {
    /// Returns the "Pride and Prejudice" audiobook so the caller can load it into the player,
    /// or nil if seeding did not run (flag absent) or failed.
    @MainActor
    static func seedIfNeeded(modelContainer: ModelContainer) async -> Audiobook? {
        guard ProcessInfo.processInfo.environment["UITEST_SEED_SCREENSHOTS"] == "1" else { return nil }
        // Each capture starts from LibriVox and exercises the real server connection UI anew.
        UserDefaults.standard.set("librivox", forKey: ShelvesSourcePreference.storageKey)
        ABSAccount.shared.disconnect()
        let context = modelContainer.mainContext
        return await seed(context: context)
    }

    private struct BookSpec {
        let title: String
        let author: String
        /// One entry per chapter/track, in minutes.
        let chapterMinutes: [Double]
        let progressFraction: Double
        let isFavorite: Bool
        let isFinished: Bool
        let playedRecently: Bool
    }

    // Source audio is short for fast capture. Display duration and apparent file size are
    // synthetic metadata, confined to this DEBUG-only path.
    private static let specs: [BookSpec] = [
        BookSpec(title: "Meditations", author: "Marcus Aurelius", chapterMinutes: [11], progressFraction: 0.22, isFavorite: true, isFinished: false, playedRecently: false),
        BookSpec(title: "The Prince", author: "Niccolò Machiavelli", chapterMinutes: [9], progressFraction: 0.12, isFavorite: false, isFinished: false, playedRecently: false),
        BookSpec(title: "Walden", author: "Henry David Thoreau", chapterMinutes: [6, 6, 6], progressFraction: 0.74, isFavorite: true, isFinished: false, playedRecently: false),
        BookSpec(title: "Notes from the Underground", author: "Fyodor Dostoevsky", chapterMinutes: [7, 7], progressFraction: 0.0, isFavorite: false, isFinished: false, playedRecently: false),
        BookSpec(title: "The Odyssey", author: "Homer, trans. Samuel Butler", chapterMinutes: [5, 5, 5, 5], progressFraction: 1.0, isFavorite: false, isFinished: true, playedRecently: false),
        BookSpec(title: "Pride and Prejudice", author: "Jane Austen", chapterMinutes: [7, 7, 7], progressFraction: 0.38, isFavorite: true, isFinished: false, playedRecently: true),
    ]

    @MainActor
    private static func seed(context: ModelContext) async -> Audiobook? {
        clearExistingLibrary(context: context)

        var pride: Audiobook?
        for spec in specs {
            guard let audiobook = try? await importBook(spec, context: context) else { continue }
            applyProgress(spec, to: audiobook)
            if spec.title == "Pride and Prejudice" { pride = audiobook }
        }
        try? context.save()

        if let pride {
            seedMoments(on: pride, context: context)
            try? context.save()
        }

        return pride
    }

    private static func clearExistingLibrary(context: ModelContext) {
        let books = (try? context.fetch(FetchDescriptor<Audiobook>())) ?? []
        for book in books {
            try? LibraryImportService.deleteAudiobook(book, deleteFiles: true, modelContext: context)
        }
        try? context.save()
    }

    // MARK: - Import

    private static func importBook(_ spec: BookSpec, context: ModelContext) async throws -> Audiobook {
        // Uniqueness lives in the per-book subdirectory, not a UUID-prefixed filename — the track
        // title import path falls back to the source file's name (sans extension) when there is no
        // embedded metadata title, so a UUID prefix would otherwise leak into the UI as the chapter
        // title (e.g. a mini-player subtitle reading "3F2A…-Chapter 2").
        let bookDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
        let urls = try spec.chapterMinutes.enumerated().map { index, minutes in
            try makeSilentAudioFile(
                minutes: minutes,
                directory: bookDir,
                fileName: spec.chapterMinutes.count > 1 ? "Chapter \(index + 1).m4a" : "\(spec.title).m4a"
            )
        }
        let pending = try await LibraryImportService.prepareImport(from: urls)
        let audiobook = try LibraryImportService.importAudiobook(
            from: pending,
            title: spec.title,
            author: spec.author,
            modelContext: context
        )
        let realisticHours: Double
        let apparentMB: UInt64
        switch spec.title {
        case "Meditations": (realisticHours, apparentMB) = (5.2, 146)
        case "The Prince": (realisticHours, apparentMB) = (3.8, 108)
        case "Walden": (realisticHours, apparentMB) = (14.5, 410)
        case "Notes from the Underground": (realisticHours, apparentMB) = (5.4, 151)
        case "The Odyssey": (realisticHours, apparentMB) = (11.1, 312)
        default: (realisticHours, apparentMB) = (11.2, 318)
        }
        for (index, track) in audiobook.sortedTracks.enumerated() {
            track.duration = realisticHours * 3600 / Double(audiobook.sortedTracks.count)
            if spec.title == "Pride and Prejudice" { track.title = "Chapter \(index + 11)" }
        }
        audiobook.totalDuration = realisticHours * 3600
        // The library badge reads folder file sizes. A sparse placeholder gives a plausible
        // displayed size without generating hundreds of megabytes of audio data.
        if let support = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                       in: .userDomainMask, appropriateFor: nil, create: false) {
            let folder = support.appendingPathComponent("Audiobooks").appendingPathComponent(audiobook.folderName)
            let placeholder = folder.appendingPathComponent("capture-size.dat")
            FileManager.default.createFile(atPath: placeholder.path, contents: nil)
            let handle = try FileHandle(forWritingTo: placeholder)
            try handle.truncate(atOffset: apparentMB * 1024 * 1024)
            try handle.close()
        }
        try? FileManager.default.removeItem(at: bookDir)
        return audiobook
    }

    private static func applyProgress(_ spec: BookSpec, to audiobook: Audiobook) {
        let tracks = audiobook.sortedTracks
        guard !tracks.isEmpty else { return }
        audiobook.isFavorite = spec.isFavorite
        audiobook.isFinished = spec.isFinished
        if spec.title == "Pride and Prejudice" {
            audiobook.equalizerConfiguration = .preset(.voiceBoost, preampDB: 2, isEnabled: true)
        }

        if spec.isFinished {
            audiobook.currentTrackIndex = tracks.count - 1
            audiobook.currentTime = tracks.last?.duration ?? 0
        } else if spec.progressFraction <= 0 {
            audiobook.currentTrackIndex = 0
            audiobook.currentTime = 0
        } else if spec.title == "Pride and Prejudice" {
            // The short silent capture track supports an actual mid-chapter player position.
            audiobook.currentTrackIndex = 1
            audiobook.currentTime = 240
        } else {
            let targetElapsed = audiobook.totalDuration * spec.progressFraction
            var remaining = targetElapsed
            var trackIndex = 0
            for (index, track) in tracks.enumerated() {
                if remaining <= track.duration {
                    trackIndex = index
                    break
                }
                remaining -= track.duration
                trackIndex = index
            }
            audiobook.currentTrackIndex = trackIndex
            audiobook.currentTime = max(0, min(remaining, tracks[trackIndex].duration - 1))
        }

        if spec.playedRecently || spec.progressFraction > 0 || spec.isFinished {
            audiobook.lastPlayedAt = spec.playedRecently ? .now : .now.addingTimeInterval(-Double.random(in: 3600...86_400 * 4))
        }
    }

    // MARK: - Moments (Pride and Prejudice, real public-domain quotes)

    private static func seedMoments(on audiobook: Audiobook, context: ModelContext) {
        struct Seed {
            let label: String
            let time: Double
            let trackIndex: Int
            let note: String
            let quote: String
            let categories: [MomentCategory]
            let mood: MomentMood
            let characters: [String]
        }

        let seeds: [Seed] = [
            Seed(
                label: "A Truth Universally Acknowledged",
                time: 42,
                trackIndex: 0,
                note: "The opening line — dry, sharp, and instantly funny.",
                quote: "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
                categories: [.humor, .quote],
                mood: .funny,
                characters: ["Mr. Bennet", "Mrs. Bennet"]
            ),
            Seed(
                label: "Mr. Darcy's Pride",
                time: 260,
                trackIndex: 0,
                note: "Elizabeth's first real read on Darcy — pride meeting pride.",
                quote: "I could easily forgive his pride, if he had not mortified mine.",
                categories: [.dialogue, .tension],
                mood: .tense,
                characters: ["Elizabeth Bennet", "Mr. Darcy"]
            ),
            Seed(
                label: "Bewitched, Body and Soul",
                time: 190,
                trackIndex: 1,
                note: "Darcy's second proposal — the one that lands.",
                quote: "You have bewitched me, body and soul.",
                categories: [.romance, .quote],
                mood: .romantic,
                characters: ["Mr. Darcy", "Elizabeth Bennet"]
            ),
            Seed(
                label: "Standing Her Ground",
                time: 410,
                trackIndex: 2,
                note: "Elizabeth refuses to be intimidated by Lady Catherine.",
                quote: "I am not to be intimidated into anything so wholly unreasonable.",
                categories: [.dialogue, .characterIntro],
                mood: .dramatic,
                characters: ["Elizabeth Bennet", "Lady Catherine"]
            ),
        ]

        for seed in seeds {
            let moment = Moment(
                trackIndex: seed.trackIndex,
                time: seed.time,
                label: seed.label,
                audiobook: audiobook,
                aiGeneratedName: true,
                notes: seed.note,
                categories: seed.categories,
                quoteLine: seed.quote,
                characters: seed.characters,
                mood: seed.mood
            )
            context.insert(moment)
            audiobook.moments.append(moment)
        }
    }

    // MARK: - Synthetic audio

    /// Writes a silent AAC (.m4a) file of the given length directly via AVAudioFile — no bundled
    /// fixture, no external tool. Placeholder audio only; screenshots never expose sound.
    private static func makeSilentAudioFile(minutes: Double, directory: URL, fileName: String) throws -> URL {
        let sampleRate = 44_100.0
        let url = directory.appendingPathComponent(fileName)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let totalFrames = AVAudioFrameCount((minutes * 60) * sampleRate)
        let chunkFrames: AVAudioFrameCount = AVAudioFrameCount(sampleRate * 20) // 20s chunks
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = chunkFrames // zeroed by default — silence

        var written: AVAudioFrameCount = 0
        while written < totalFrames {
            let remaining = totalFrames - written
            if remaining < chunkFrames {
                guard let lastBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: remaining) else { break }
                lastBuffer.frameLength = remaining
                try file.write(from: lastBuffer)
                written += remaining
            } else {
                try file.write(from: buffer)
                written += chunkFrames
            }
        }
        return url
    }
}
#endif
