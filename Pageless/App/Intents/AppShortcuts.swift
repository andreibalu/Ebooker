//
//  AppShortcuts.swift
//  Pageless
//

import AppIntents

struct PagelessShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumePlaybackIntent(),
            phrases: [
                "Resume my audiobook in \(.applicationName)",
                "Continue listening in \(.applicationName)",
                "Play my book in \(.applicationName)",
            ],
            shortTitle: "Resume Listening",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: PlayAudiobookIntent(),
            phrases: [
                "Play \(\.$audiobook) in \(.applicationName)",
                "Listen to \(\.$audiobook) in \(.applicationName)",
            ],
            shortTitle: "Play Audiobook",
            systemImageName: "book.fill"
        )

        AppShortcut(
            intent: PausePlaybackIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Stop my audiobook in \(.applicationName)",
            ],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )

        AppShortcut(
            intent: OpenLibraryIntent(),
            phrases: [
                "Open my library in \(.applicationName)",
                "Show my audiobooks in \(.applicationName)",
            ],
            shortTitle: "Open Library",
            systemImageName: "books.vertical.fill"
        )
    }
}
