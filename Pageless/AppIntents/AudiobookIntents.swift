//
//  AudiobookIntents.swift
//  Pageless
//

import AppIntents

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
