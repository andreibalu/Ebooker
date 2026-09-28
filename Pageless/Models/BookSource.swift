import Foundation

/// One browsable catalog behind the Shelves tab.
///
/// Deliberately a plain descriptor rather than a protocol that builds its own view: each source's
/// root view has different dependencies (LibriVox needs its `BrowseLibriVoxViewModel`, a server
/// source would need a client plus stored credentials), so view construction stays in
/// `ContentView.tabPage` where those dependencies already live. Adding a source = one entry in
/// `BookSourceRegistry.sources` plus one branch there.
struct BookSource: Identifiable, Hashable {
    let id: String
    let name: String
    /// False while a source still needs setup (a server URL, credentials) before it can browse.
    /// Unconfigured sources stay listed in the Shelves menu but cannot be selected.
    let isConfigured: Bool
}

enum BookSourceRegistry {
    static let librivox = BookSource(id: "librivox", name: "LibriVox", isConfigured: true)

    static var sources: [BookSource] { [librivox] }
}

enum ShelvesSourcePreference {
    static let storageKey = "shelvesSource"
    static let defaultSourceID = BookSourceRegistry.librivox.id

    /// Falls back to LibriVox when the stored id names a source that no longer exists or is not yet
    /// configured, so a stale preference can never leave the tab blank.
    static func resolvedSourceID(_ storedID: String, from sources: [BookSource]) -> String {
        if let source = sources.first(where: { $0.id == storedID && $0.isConfigured }) {
            return source.id
        }
        if let defaultSource = sources.first(where: { $0.id == defaultSourceID }) {
            return defaultSource.id
        }
        return sources.first(where: \.isConfigured)?.id ?? defaultSourceID
    }
}
