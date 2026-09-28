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

        let sources = BookSourceRegistry.sources
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

    @Test func registryProvidesLibriVoxAsItsOnlyConfiguredSource() {
        let sources = BookSourceRegistry.sources

        #expect(sources.map(\.id) == ["librivox"])
        #expect(sources.first?.name == "LibriVox")
        #expect(sources.first?.isConfigured == true)
    }

    @Test func aSingleRegisteredSourceOffersNoChoice() {
        // The Shelves tab only grows its chevron + source menu once there is something to switch
        // between; today LibriVox is alone, so the tab behaves like any other tab.
        #expect(BookSourceRegistry.sources.count == 1)
    }

    @Test func unconfiguredSourceNeverResolvesAsTheSelection() {
        let pending = BookSource(id: "audiobookshelf", name: "Audiobookshelf", isConfigured: false)
        let sources = BookSourceRegistry.sources + [pending]

        #expect(ShelvesSourcePreference.resolvedSourceID("audiobookshelf", from: sources) == "librivox")
    }
}
