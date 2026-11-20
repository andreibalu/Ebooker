//
//  SaveMomentIntent.swift
//  Pageless
//

import AppIntents
import SwiftData
import UIKit

@MainActor
enum SaveMomentAction {
    static let intentFlagKey = "intent.saveMoment"
    static let intentNoteKey = "intent.saveMomentNote"
    static let notificationName = Notification.Name("UnpagedSaveMoment")
    static let savedNotificationName = Notification.Name("UnpagedMomentSavedByIntent")

    struct SavedResult {
        let bookTitle: String
        let savedTime: Double
        let label: String
    }

    @discardableResult
    static func saveCurrentMoment(
        player: AudioPlayerManager,
        modelContext: ModelContext,
        note: String? = nil
    ) -> SavedResult? {
        let target: (book: Audiobook, trackIndex: Int, rawTime: Double, chapterTitle: String?)?

        if let activeBook = player.currentAudiobook {
            let chapterTitle = player.currentChapter?.title ?? player.currentTrack?.displayTitle
            target = (activeBook, player.currentTrackIndex, player.currentTime, chapterTitle)
        } else {
            let descriptor = FetchDescriptor<Audiobook>(
                sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
            )
            if let latest = try? modelContext.fetch(descriptor).first(where: {
                $0.isInActiveLibrary && ($0.lastPlayedAt != nil || $0.currentTime > 0 || $0.currentTrackIndex > 0)
            }) {
                let tracks = latest.sortedTracks
                let chapterTitle = tracks.indices.contains(latest.currentTrackIndex)
                    ? tracks[latest.currentTrackIndex].displayTitle
                    : nil
                target = (latest, latest.currentTrackIndex, latest.currentTime, chapterTitle)
            } else {
                target = nil
            }
        }

        guard let target else { return nil }

        let backtrack = UserDefaults.standard.double(forKey: "momentBacktrackSeconds")
        let savedTime = max(target.rawTime - backtrack, 0)
        let fallback = MomentFallbackNamer.analysis(
            transcript: nil,
            chapterTitle: target.chapterTitle,
            time: savedTime
        )
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)

        let moment = Moment(
            trackIndex: target.trackIndex,
            time: savedTime,
            label: fallback.name,
            audiobook: target.book,
            transcript: nil,
            aiGeneratedName: false,
            notes: trimmedNote?.isEmpty == false ? trimmedNote : nil
        )
        modelContext.insert(moment)
        try? modelContext.save()

        if UIApplication.shared.applicationState == .active {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        NotificationCenter.default.post(name: savedNotificationName, object: nil)

        return SavedResult(bookTitle: target.book.title, savedTime: savedTime, label: fallback.name)
    }
}

struct SaveMomentIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Moment"
    static let description = IntentDescription("Saves a moment at your current listening position in Unpaged.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Note", description: "Optional note to attach to the saved moment.")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let delegate = AppDelegate.shared {
            if let saved = SaveMomentAction.saveCurrentMoment(
                player: delegate.audioPlayer,
                modelContext: delegate.modelContainer.mainContext,
                note: note
            ) {
                let clock = TimeFormatter.clockString(seconds: saved.savedTime)
                return .result(dialog: "Saved moment at \(clock) in \(saved.bookTitle).")
            }
            return .result(dialog: "No audiobook is playing in Unpaged.")
        }

        let sharedDefaults = UserDefaults(suiteName: "group.andreibaludev.Pageless")
        UserDefaults.standard.set(true, forKey: SaveMomentAction.intentFlagKey)
        sharedDefaults?.set(true, forKey: SaveMomentAction.intentFlagKey)
        if let note, !note.isEmpty {
            UserDefaults.standard.set(note, forKey: SaveMomentAction.intentNoteKey)
            sharedDefaults?.set(note, forKey: SaveMomentAction.intentNoteKey)
        }
        NotificationCenter.default.post(name: SaveMomentAction.notificationName, object: nil)
        return .result(dialog: "Saving moment in Unpaged.")
    }
}
