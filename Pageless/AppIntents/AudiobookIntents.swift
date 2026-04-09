//
//  AudiobookIntents.swift
//  Pageless
//

import AppIntents

struct PlayLatestBookIntent: AppIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Latest Book"
    static let description = IntentDescription("Plays your most recently listened audiobook in Unpaged.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "intent.playLatestBook")
        return .result()
    }
}

struct UnpagedAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayLatestBookIntent(),
            phrases: [
                "Play in \(.applicationName)",
                "Play my latest book in \(.applicationName)",
                "Resume my book in \(.applicationName)",
                "Continue listening in \(.applicationName)",
            ],
            shortTitle: "Play Latest Book",
            systemImageName: "headphones"
        )
    }
}
