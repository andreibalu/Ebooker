#if DEBUG
import Foundation
import SwiftData

/// Opt-in fixtures for the dedicated E2E simulator. Shipping builds contain no launch hooks.
@MainActor
enum E2EFixtures {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-e2e-fixture") }

    static func storeDirectory(in support: URL) throws -> URL {
        let directory = support.appendingPathComponent("E2EFixtures", isDirectory: true)
        if ProcessInfo.processInfo.arguments.contains("-e2e-reset-fixture") {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            // UIKit scene restoration would otherwise reopen whatever screen the previous run
            // ended on (for example Reading stats), so a reset must also start from the root.
            let savedState = support.deletingLastPathComponent()
                .appendingPathComponent("Saved Application State", isDirectory: true)
            if FileManager.default.fileExists(atPath: savedState.path) {
                try FileManager.default.removeItem(at: savedState)
            }
            // A reset run starts with no Audiobookshelf server; the fixture login is separate.
            try? ABSKeychainCredentialStore().clear()
            // Onboarding and the ABS library menu write these; a reset run must see the defaults again.
            for key in ["resumeBacktrackSeconds", "skipBackSeconds", "skipForwardSeconds", "momentBacktrackSeconds",
                        "absSelectedLibraryID"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func seedIfNeeded(_ context: ModelContext) throws {
        let marker = try storeDirectoryWithoutReset()
            .appendingPathComponent("seeded")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let book = Audiobook(title: "E2E The Listening Book", author: "Fixture Author",
                             folderName: "E2E-Listening-Book", totalDuration: 600,
                             isFavorite: true)
        context.insert(book)
        let audioDirectory = LibraryMutationTransaction.defaultAudiobooksRoot()
            .appendingPathComponent(book.folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        for index in 0..<2 {
            let name = "chapter-\(index).wav"
            try silenceWAV(seconds: 300).write(to: audioDirectory.appendingPathComponent(name))
            let track = AudioTrack(title: "E2E Chapter \(index + 1)", originalFileName: name,
                                   storedFileName: name, orderIndex: index, duration: 300,
                                   audiobook: book)
            context.insert(track)
            book.tracks.append(track)
        }
        let moment = Moment(trackIndex: 0, time: 30, label: "E2E First Moment",
                            audiobook: book, notes: "A saved fixture note", categories: [.dialogue])
        context.insert(moment)
        book.moments.append(moment)
        let secondMoment = Moment(trackIndex: 0, time: 60, label: "E2E Second Moment",
                                  audiobook: book, categories: [.reflection])
        context.insert(secondMoment)
        book.moments.append(secondMoment)
        let secondBook = Audiobook(title: "E2E Another Book", author: "Another Fixture Author",
                                   folderName: "E2E-Another-Book", totalDuration: 300)
        context.insert(secondBook)
        let secondAudioDirectory = LibraryMutationTransaction.defaultAudiobooksRoot()
            .appendingPathComponent(secondBook.folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: secondAudioDirectory, withIntermediateDirectories: true)
        try silenceWAV(seconds: 300).write(to: secondAudioDirectory.appendingPathComponent("chapter.wav"))
        let secondTrack = AudioTrack(title: "E2E Another Chapter", originalFileName: "chapter.wav",
                                     storedFileName: "chapter.wav", orderIndex: 0, duration: 300,
                                     audiobook: secondBook)
        context.insert(secondTrack)
        secondBook.tracks.append(secondTrack)
        let today = Calendar.current.startOfDay(for: .now)
        context.insert(ReadingSession(date: today, dayKey: ReadingSession.makeDayKey(date: today),
                                      hour: 10, minutes: 42, bookID: book.id,
                                      bookTitle: book.title, bookAuthor: book.author, isFreeBook: false))
        for row in catalogRows {
            context.insert(LibriVoxBook(id: row.id, title: row.title, authorDisplay: row.author,
                                        bookDescription: row.description, language: row.language,
                                        totalTimeSecs: row.seconds, genres: row.genres))
        }
        try context.save()
        try Data().write(to: marker)
    }

    /// Every curated classic (so any day's pick resolves), the full Love & Society shelf, an
    /// alternate recording of Pride and Prejudice, and one German book for the language filter.
    /// IDs match the live feed; e2e/fake-librivox serves the same rows when tests go "online".
    private static let catalogRows: [(id: String, title: String, author: String, description: String,
                                      language: String, seconds: Int, genres: [String])] = [
        ("253", "Pride and Prejudice", "Jane Austen", "An offline cached public-domain classic.",
         "English", 47204, ["General Fiction"]),
        ("314", "Adventures of Sherlock Holmes", "Arthur Conan Doyle", "Twelve cases from Baker Street.",
         "English", 37800, ["Detective Fiction"]),
        ("133", "Jane Eyre", "Charlotte Brontë", "An orphan governess and Thornfield Hall.",
         "English", 68400, ["Romance"]),
        ("381", "Frankenstein, or The Modern Prometheus", "Mary Shelley", "A creature and its maker.",
         "English", 30600, ["Horror & Supernatural Fiction"]),
        ("271", "Dracula", "Bram Stoker", "Letters and diaries from Transylvania.",
         "English", 55800, ["Horror & Supernatural Fiction"]),
        ("449", "Treasure Island", "Robert Louis Stevenson", "A map, a cook and a mutiny.",
         "English", 25200, ["Action & Adventure Fiction"]),
        ("436", "War of the Worlds", "H. G. Wells", "Cylinders fall on Surrey.",
         "English", 22800, ["Science Fiction"]),
        ("510", "Tale of Two Cities", "Charles Dickens", "London, Paris and the Revolution.",
         "English", 57600, ["Historical Fiction"]),
        ("661", "Persuasion", "Jane Austen", "Anne Elliot, eight years later.",
         "English", 30000, ["Romance"]),
        ("620", "Sense and Sensibility", "Jane Austen", "Two Dashwood sisters.",
         "English", 42000, ["Romance"]),
        ("86", "Emma", "Jane Austen", "Highbury's matchmaker.",
         "English", 57000, ["Romance"]),
        ("911", "Wuthering Heights", "Emily Brontë", "The moors and Heathcliff.",
         "English", 44000, ["Romance"]),
        ("2531", "Pride and Prejudice (version 2)", "Jane Austen", "A second full-cast recording.",
         "English", 45000, ["General Fiction"]),
        ("1203", "Die Verwandlung", "Franz Kafka", "Gregor Samsa erwacht als Ungeziefer.",
         "German", 7200, ["Short Stories"]),
    ]

    /// The file the DEBUG import button hands to the import pipeline. `-e2e-import-file <name>`
    /// picks a file the test copied into the fixture directory (for example a chaptered M4B);
    /// otherwise a generated 123-second WAV.
    static func importSource() throws -> URL {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-e2e-import-file"), arguments.indices.contains(index + 1) {
            let name = (arguments[index + 1] as NSString).lastPathComponent
            return try storeDirectoryWithoutReset().appendingPathComponent(name)
        }
        let url = try storeDirectoryWithoutReset().appendingPathComponent("E2E Import.wav")
        try silenceWAV(seconds: 123).write(to: url)
        return url
    }

    private static func storeDirectoryWithoutReset() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent("E2EFixtures", isDirectory: true)
    }

    /// Real PCM audio exercises AVPlayer, track transitions, seeking and EQ without downloads.
    private static func silenceWAV(seconds: Int) -> Data {
        let samples = seconds * 8_000
        let byteCount = UInt32(samples * 2)
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); integer(byteCount + 36); text("WAVEfmt ")
        integer(UInt32(16)); integer(UInt16(1)); integer(UInt16(1))
        integer(UInt32(8_000)); integer(UInt32(16_000)); integer(UInt16(2)); integer(UInt16(16))
        text("data"); integer(byteCount)
        data.append(Data(count: Int(byteCount)))
        return data
    }
}
#endif
