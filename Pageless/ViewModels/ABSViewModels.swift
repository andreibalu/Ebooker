//
//  ABSViewModels.swift
//  Pageless
//
//  View models for the Audiobookshelf shelf: connect sheet, browse, and book detail.
//

import Foundation
import SwiftData
import UIKit

// MARK: - Connect

@MainActor
@Observable
final class ABSConnectViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn
        case apiKey

        var id: String { rawValue }
        var title: String { self == .signIn ? "Sign in" : "API key" }
    }

    /// Which field an error belongs under. Errors are always shown inline, never as alerts.
    enum Field: Equatable {
        case server
        case username
        case password
        case apiKey
    }

    struct FieldError: Equatable {
        let field: Field
        let message: String
    }

    var serverText: String
    var username = ""
    var password = ""
    var apiKey = ""
    var mode: Mode = .signIn
    private(set) var isConnecting = false
    private(set) var error: FieldError?

    init(serverText: String = "") {
        self.serverText = serverText
    }

    func message(for field: Field) -> String? {
        error?.field == field ? error?.message : nil
    }

    func clearError(for field: Field) {
        if error?.field == field { error = nil }
    }

    func clearErrors() { error = nil }

    var canSubmit: Bool {
        guard !isConnecting, !serverText.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch mode {
        case .signIn: return !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
        case .apiKey: return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Returns true once a connection is stored.
    func connect(account: ABSAccount, isNetworkAvailable: Bool? = nil) async -> Bool {
        guard !isConnecting else { return false }
        let isNetworkAvailable = isNetworkAvailable ?? NetworkMonitor.shared.isConnected
        error = nil

        let url: URL
        do {
            url = try AudiobookshelfClient.serverURL(from: serverText)
        } catch {
            self.error = FieldError(field: .server, message: Self.invalidAddressMessage)
            return false
        }
        switch mode {
        case .signIn:
            if username.trimmingCharacters(in: .whitespaces).isEmpty {
                error = FieldError(field: .username, message: "Enter your Audiobookshelf username.")
                return false
            }
            if password.isEmpty {
                error = FieldError(field: .password, message: "Enter your password.")
                return false
            }
        case .apiKey:
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                error = FieldError(field: .apiKey, message: "Paste an API key from your server.")
                return false
            }
        }
        guard isNetworkAvailable else {
            error = FieldError(field: .server, message: "You're offline. Connect to Wi‑Fi or cellular and try again.")
            return false
        }

        isConnecting = true
        defer { isConnecting = false }
        do {
            switch mode {
            case .signIn:
                try await account.signIn(serverURL: url,
                                         username: username.trimmingCharacters(in: .whitespaces),
                                         password: password)
            case .apiKey:
                try await account.connect(serverURL: url,
                                          apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            password = ""
            apiKey = ""
            return true
        } catch {
            self.error = Self.fieldError(for: error, mode: mode, host: Self.displayHost(url))
            return false
        }
    }

    static let invalidAddressMessage = "That doesn't look like a server address. Try something like https://abs.example.com."

    static func fieldError(for error: Error, mode: Mode, host: String) -> FieldError {
        switch error as? AudiobookshelfError {
        case .invalidServerURL?:
            return FieldError(field: .server, message: invalidAddressMessage)
        case .unreachableServer?:
            return FieldError(field: .server, message: "Can't reach \(host). Check the address, and that the server is running and reachable from this iPhone.")
        case .offline?:
            return FieldError(field: .server, message: "You're offline. Connect to Wi‑Fi or cellular and try again.")
        case .insecureConnection?:
            return FieldError(field: .server, message: "Plain http:// only works for servers on your local network. Use your server's https:// address.")
        case .notAudiobookshelfServer?:
            return FieldError(field: .server, message: "\(host) answered, but it isn't an Audiobookshelf server. Check the address.")
        case .inactiveAPIKey?:
            return FieldError(field: .apiKey, message: "This API key is inactive — enable it in Audiobookshelf → Settings → API Keys, then try again.")
        case .badCredentials?, .expiredToken?:
            return mode == .signIn
                ? FieldError(field: .password, message: "That username and password didn't work. Check them and try again.")
                : FieldError(field: .apiKey, message: "The server didn't accept this API key. Check that you copied all of it.")
        case .serverError(let status)?:
            return FieldError(field: .server, message: "\(host) had a problem (error \(status)). Try again in a moment.")
        default:
            return FieldError(field: .server, message: "\(host) sent a reply Unpaged couldn't read. Check that it's an Audiobookshelf server.")
        }
    }

    static func displayHost(_ url: URL) -> String {
        guard let host = url.host() else { return "the server" }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }
}

// MARK: - Browse

@MainActor
@Observable
final class ABSBrowseViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case offline
        case unreachable
        case signedOut
        case noBookLibraries
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var libraries: [ABSLibrary] = []
    private(set) var selectedLibraryID: String?
    private(set) var items: [ABSLibraryItem] = []
    private(set) var progressByItemID: [String: ABSMediaProgress] = [:]
    var searchQuery = ""
    private var loadedOnce = false

    var selectedLibrary: ABSLibrary? {
        libraries.first { $0.id == selectedLibraryID }
    }

    var hasContent: Bool { !items.isEmpty }

    var continueListening: [ABSLibraryItem] {
        Self.continueListening(items: items, progress: progressByItemID)
    }

    var recentlyAdded: [ABSLibraryItem] {
        Self.recentlyAdded(items: items)
    }

    var allBooks: [ABSLibraryItem] {
        items.sorted {
            $0.media.metadata.displayTitle.localizedStandardCompare($1.media.metadata.displayTitle) == .orderedAscending
        }
    }

    var searchResults: [ABSLibraryItem] {
        Self.filter(allBooks, query: searchQuery)
    }

    var isSearching: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    func progress(for item: ABSLibraryItem) -> ABSMediaProgress? { progressByItemID[item.id] }

    func loadIfNeeded(account: ABSAccount, preferredLibraryID: String?) async {
        guard !loadedOnce else { return }
        await load(account: account, preferredLibraryID: preferredLibraryID)
    }

    func load(account: ABSAccount, preferredLibraryID: String?, isNetworkAvailable: Bool? = nil) async {
        loadedOnce = true
        let isNetworkAvailable = isNetworkAvailable ?? NetworkMonitor.shared.isConnected
        guard account.isConnected else { phase = .signedOut; return }
        guard isNetworkAvailable else { phase = .offline; return }
        if items.isEmpty { phase = .loading }
        do {
            let books = try await account.client.libraries().filter { $0.mediaType == "book" }
            libraries = books
            guard !books.isEmpty else {
                items = []
                phase = .noBookLibraries
                return
            }
            let libraryID = books.first(where: { $0.id == preferredLibraryID })?.id
                ?? books.first(where: { $0.id == selectedLibraryID })?.id
                ?? books[0].id
            selectedLibraryID = libraryID
            async let fetchedItems = account.client.allLibraryItems(libraryID: libraryID, limit: 100)
            async let fetchedProgress = try? account.client.allMediaProgress()
            let (loadedItems, loadedProgress) = try await (fetchedItems, fetchedProgress)
            items = loadedItems.filter { $0.mediaType == "book" }
            progressByItemID = Dictionary((loadedProgress ?? []).map { ($0.libraryItemId, $0) },
                                          uniquingKeysWith: { first, _ in first })
            account.reload()
            phase = .loaded
        } catch {
            phase = Self.phase(for: error)
        }
    }

    func selectLibrary(_ id: String, account: ABSAccount) async {
        guard id != selectedLibraryID else { return }
        selectedLibraryID = id
        items = []
        searchQuery = ""
        phase = .loading
        await load(account: account, preferredLibraryID: id)
    }

    static func phase(for error: Error) -> Phase {
        switch error as? AudiobookshelfError {
        case .offline?: return .offline
        case .unreachableServer?, .insecureConnection?: return .unreachable
        case .notConnected?, .badCredentials?, .expiredToken?, .inactiveAPIKey?: return .signedOut
        case .serverError(let status)? where status >= 500: return .unreachable
        default: return .failed("The server sent something Unpaged couldn't read.")
        }
    }

    static func continueListening(items: [ABSLibraryItem], progress: [String: ABSMediaProgress]) -> [ABSLibraryItem] {
        items
            .filter { progress[$0.id]?.isInProgress == true }
            .sorted { (progress[$0.id]?.lastUpdate ?? 0) > (progress[$1.id]?.lastUpdate ?? 0) }
    }

    /// Newest `limit` items — empty unless the library holds more than `limit`, because a small
    /// library already shows everything at a glance in All Books.
    static func recentlyAdded(items: [ABSLibraryItem], limit: Int = 12) -> [ABSLibraryItem] {
        guard items.count > limit else { return [] }
        return Array(items.sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }.prefix(limit))
    }

    static func filter(_ items: [ABSLibraryItem], query: String) -> [ABSLibraryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.media.metadata.title.localizedStandardContains(trimmed)
                || ($0.media.metadata.authorName ?? "").localizedStandardContains(trimmed)
        }
    }
}

// MARK: - Detail

@MainActor
@Observable
final class ABSBookDetailViewModel {
    enum ActionState: Equatable {
        case idle
        case working
    }

    let summary: ABSLibraryItem
    private(set) var item: ABSLibraryItem?
    private(set) var progress: ABSMediaProgress?
    private(set) var libraryBook: Audiobook?
    private(set) var actionState: ActionState = .idle
    var actionError: String?

    init(item: ABSLibraryItem, progress: ABSMediaProgress?) {
        self.summary = item
        self.progress = progress
    }

    var metadata: ABSBookMetadata { (item ?? summary).media.metadata }
    var media: ABSMedia { (item ?? summary).media }

    var durationSeconds: Double { media.duration ?? media.playableTracks.reduce(0) { $0 + $1.duration } }

    /// Unstarted books show "Play"; anything with a position shows "Resume".
    var primaryActionTitle: String {
        guard let book = libraryBook else {
            return (progress?.isInProgress == true) ? "Resume" : "Play"
        }
        let started = !book.isFinished && (book.currentTime > 0 || book.currentTrackIndex > 0)
        return started ? "Resume" : "Play"
    }

    /// "30% listened" / "Finished". A local library copy with its own position wins (it is what
    /// Resume plays from); otherwise the server's progress is shown.
    var listenedText: String? {
        Self.listenedText(libraryBook: libraryBook, serverProgress: progress)
    }

    static func listenedText(libraryBook: Audiobook?, serverProgress: ABSMediaProgress?) -> String? {
        if let book = libraryBook {
            if book.isFinished { return "Finished" }
            if book.listenedDuration > 0, book.totalDuration > 0 {
                return percentText(book.progress)
            }
        }
        guard let serverProgress else { return nil }
        if serverProgress.isFinished { return "Finished" }
        if serverProgress.isInProgress { return percentText(serverProgress.progress) }
        return nil
    }

    private static func percentText(_ fraction: Double) -> String {
        let percent = min(max(TimeFormatter.percentValue(fraction), 1), 99)
        return "\(percent)% listened"
    }

    func refreshLibraryBook(modelContext: ModelContext) {
        libraryBook = try? AudiobookshelfLibraryService.existingBook(itemID: summary.id, modelContext: modelContext)
    }

    func load(account: ABSAccount, modelContext: ModelContext) async {
        refreshLibraryBook(modelContext: modelContext)
        async let expanded = try? account.client.item(id: summary.id)
        async let serverProgress = try? account.client.mediaProgress(itemID: summary.id)
        let (loadedItem, loadedProgress) = await (expanded, serverProgress)
        if let loadedItem { item = loadedItem }
        if let loadedProgress { progress = loadedProgress }
    }

    /// Adds the item as a streaming book (or returns the existing row). Nil on failure, with
    /// `actionError` set in plain words.
    func addToLibrary(account: ABSAccount, modelContext: ModelContext) async -> Audiobook? {
        if let libraryBook { return libraryBook }
        guard NetworkMonitor.shared.isConnected else {
            actionError = "You're offline. Connect to the internet to add books from your server."
            return nil
        }
        actionState = .working
        defer { actionState = .idle }
        do {
            let expanded: ABSLibraryItem
            if let item, !item.media.playableTracks.isEmpty {
                expanded = item
            } else {
                expanded = try await account.client.item(id: summary.id)
                item = expanded
            }
            var urls: [URL] = []
            for track in expanded.media.playableTracks {
                urls.append(try await account.client.storedStreamURL(for: track))
            }
            let latestProgress = (try? await account.client.mediaProgress(itemID: summary.id)) ?? progress
            let cover = expanded.media.hasCover ? await ABSCoverStore.shared.data(itemID: summary.id, client: account.client) : nil
            let book = try AudiobookshelfLibraryService.addToLibrary(
                item: expanded,
                trackURLs: urls,
                progress: latestProgress,
                coverArtData: cover,
                modelContext: modelContext
            )
            libraryBook = book
            actionError = nil
            return book
        } catch {
            actionError = Self.message(for: error)
            return nil
        }
    }

    static func message(for error: Error) -> String {
        switch error as? AudiobookshelfError {
        case .offline?: return "You're offline. Connect to the internet and try again."
        case .unreachableServer?: return "Can't reach your Audiobookshelf server right now."
        case .badCredentials?, .expiredToken?, .notConnected?, .inactiveAPIKey?:
            return "Your Audiobookshelf sign-in has expired. Reconnect in Settings."
        case .invalidMediaURL?: return "This book has no audio Unpaged can stream."
        default: return "Unpaged couldn't add this book. Try again in a moment."
        }
    }
}

// MARK: - Covers

/// In-memory cover cache. Covers are fetched with the auth header (`coverRequest`), never a
/// token URL, and de-duplicated while in flight.
@MainActor
final class ABSCoverStore {
    static let shared = ABSCoverStore()

    private let images = NSCache<NSString, UIImage>()
    private var data: [String: Data] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var missing: Set<String> = []

    func cachedImage(itemID: String) -> UIImage? { images.object(forKey: itemID as NSString) }

    func image(itemID: String, client: AudiobookshelfClient) async -> UIImage? {
        if let cached = cachedImage(itemID: itemID) { return cached }
        guard let bytes = await self.data(itemID: itemID, client: client),
              let image = UIImage(data: bytes) else { return nil }
        images.setObject(image, forKey: itemID as NSString)
        return image
    }

    func data(itemID: String, client: AudiobookshelfClient) async -> Data? {
        if let cached = data[itemID] { return cached }
        if missing.contains(itemID) { return nil }
        if let task = inFlight[itemID] { return await task.value }
        let task = Task<Data?, Never> {
            guard let request = try? await client.coverRequest(itemID: itemID, width: 600),
                  let (bytes, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  UIImage(data: bytes) != nil else { return nil }
            return bytes
        }
        inFlight[itemID] = task
        let result = await task.value
        inFlight[itemID] = nil
        if let result { data[itemID] = result } else { missing.insert(itemID) }
        return result
    }

    func removeAll() {
        images.removeAllObjects()
        data.removeAll()
        missing.removeAll()
    }
}
