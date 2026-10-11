//
//  PlayLatestBookIntent.swift
//  Pageless
//
//  Compiled into the app and the widget extension (the Continue Listening Play button).
//  `UnpagedAppShortcuts` stays app-only in AudiobookIntents.swift.
//

import AppIntents

struct PlayLatestBookIntent: AppIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Latest Book"
    static let description = IntentDescription("Plays your most recently listened audiobook in Unpaged.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "intent.playLatestBook")
        UserDefaults(suiteName: "group.andreibaludev.Pageless")?.set(true, forKey: "intent.playLatestBook")
        NotificationCenter.default.post(name: Notification.Name("UnpagedPlayLatestBook"), object: nil)
        return .result()
    }
}
