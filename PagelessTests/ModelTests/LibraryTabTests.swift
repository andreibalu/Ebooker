import Foundation
import Testing
@testable import Pageless

@MainActor
struct LibraryTabTests {
    @Test func visibleTitlesUseLibraryNaming() {
        #expect(LibraryTab.favorites.title == "Favorites")
        #expect(LibraryTab.allBooks.title == "Library")
        #expect(LibraryTab.freeBooks.title == "Shelves")
    }

    @Test func tabOrderKeepsTheExistingHomePreference() {
        #expect(LibraryTab.order(startOnFreeBooks: true) == [.favorites, .freeBooks, .allBooks])
        #expect(LibraryTab.order(startOnFreeBooks: false) == [.favorites, .allBooks, .freeBooks])
    }

    @Test func sourcePreferencePersistsAndUnknownValuesResolveToLibriVox() {
        let suiteName = "test.shelves-source.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let sources = BookSourceRegistry.sources(isAudiobookshelfConfigured: false)
        defaults.set("librivox", forKey: ShelvesSourcePreference.storageKey)

        #expect(defaults.string(forKey: ShelvesSourcePreference.storageKey) == "librivox")
        #expect(ShelvesSourcePreference.resolvedSourceID(
            defaults.string(forKey: ShelvesSourcePreference.storageKey) ?? "",
            from: sources
        ) == "librivox")

        defaults.set("unknown-source", forKey: ShelvesSourcePreference.storageKey)
        #expect(ShelvesSourcePreference.resolvedSourceID(
            defaults.string(forKey: ShelvesSourcePreference.storageKey) ?? "",
            from: sources
        ) == "librivox")
    }

    @Test func registryListsLibriVoxThenAudiobookshelf() {
        let sources = BookSourceRegistry.sources(isAudiobookshelfConfigured: false)

        #expect(sources.map(\.id) == ["librivox", "audiobookshelf"])
        #expect(sources.first?.name == "LibriVox")
        #expect(sources.first?.isConfigured == true)
        #expect(sources.last?.name == "Audiobookshelf")
        #expect(sources.last?.isConfigured == false)
        #expect(BookSourceRegistry.sources(isAudiobookshelfConfigured: true).last?.isConfigured == true)
    }

    @Test func configuredAudiobookshelfIsHonouredAndSurvivesDisconnect() {
        let connected = BookSourceRegistry.sources(isAudiobookshelfConfigured: true)
        #expect(ShelvesSourcePreference.resolvedSourceID("audiobookshelf", from: connected) == "audiobookshelf")
        #expect(ShelvesSourcePreference.resolvedSourceID("librivox", from: connected) == "librivox")

        // After Disconnect the stored id stays, but resolves to LibriVox so the tab is never blank.
        let disconnected = BookSourceRegistry.sources(isAudiobookshelfConfigured: false)
        #expect(ShelvesSourcePreference.resolvedSourceID("audiobookshelf", from: disconnected) == "librivox")
    }
}
