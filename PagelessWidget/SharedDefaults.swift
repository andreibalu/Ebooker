//
//  SharedDefaults.swift
//  Pageless
//
//  Reads/writes shared data to App Group UserDefaults so the widget
//  extension can display library and now-playing information.
//

import Foundation
import WidgetKit

enum SharedDefaults {
    static let suiteName = "group.andreibaludev.pageless"

    private static let libraryKey = "sharedLibrary"
    private static let nowPlayingKey = "sharedNowPlaying"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    // MARK: - Library

    static func saveLibrary(_ books: [SharedBookData]) {
        guard let data = try? JSONEncoder().encode(books) else { return }
        defaults?.set(data, forKey: libraryKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func loadLibrary() -> [SharedBookData] {
        guard let data = defaults?.data(forKey: libraryKey),
              let books = try? JSONDecoder().decode([SharedBookData].self, from: data)
        else { return [] }
        return books
    }

    // MARK: - Now Playing

    static func saveNowPlaying(_ nowPlaying: SharedNowPlayingData?) {
        if let nowPlaying, let data = try? JSONEncoder().encode(nowPlaying) {
            defaults?.set(data, forKey: nowPlayingKey)
        } else {
            defaults?.removeObject(forKey: nowPlayingKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func loadNowPlaying() -> SharedNowPlayingData? {
        guard let data = defaults?.data(forKey: nowPlayingKey),
              let nowPlaying = try? JSONDecoder().decode(SharedNowPlayingData.self, from: data)
        else { return nil }
        return nowPlaying
    }
}
