import Foundation
import Testing
@testable import Pageless

@MainActor
struct LibraryTabTests {
    @Test func sourcePreferencePersistsAndUnknownValuesResolveToLibriVox() {
        let suiteName = "test.shelves-source.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let sources = BookSourceRegistry.sources(isAudiobookshelfConfigured: false)
        defaults.set("unknown-source", forKey: ShelvesSourcePreference.storageKey)
        #expect(ShelvesSourcePreference.resolvedSourceID(
            defaults.string(forKey: ShelvesSourcePreference.storageKey) ?? "",
            from: sources
        ) == "librivox")
    }
}
