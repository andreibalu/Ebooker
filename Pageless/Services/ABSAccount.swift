//
//  ABSAccount.swift
//  Pageless
//

import Foundation
import Observation
import OSLog

/// The app's single Audiobookshelf connection, observable by SwiftUI.
///
/// Owns the shared `AudiobookshelfClient` and mirrors only the *display* half of the Keychain
/// record (server URL + username) — the token itself is never copied out of the client/Keychain.
/// A singleton for the same reason as `ICloudSubscriptionStore`: `AudioPlayerManager` and the
/// Shelves source registry need it outside the SwiftUI environment.
@MainActor
@Observable
final class ABSAccount {
    static let shared = ABSAccount()

    struct Summary: Equatable {
        let baseURL: URL
        let username: String?
        let usesAPIKey: Bool

        var host: String {
            guard let host = baseURL.host() else { return baseURL.absoluteString }
            if let port = baseURL.port { return "\(host):\(port)" }
            return host
        }

        /// The account queued progress belongs to: a different user on the same server is a
        /// different account, so their queued positions must never be sent with these credentials.
        var progressAccount: ABSProgressAccount { ABSProgressAccount(server: baseURL.absoluteString, username: username) }
    }

    let client: AudiobookshelfClient
    private let credentials: any ABSCredentialStoring
    private(set) var summary: Summary?

    var isConnected: Bool { summary != nil }

    init(credentials: any ABSCredentialStoring = ABSKeychainCredentialStore(), session: URLSession = .shared) {
        self.credentials = credentials
        self.client = AudiobookshelfClient(session: session, credentials: credentials)
        reload()
    }

    /// Re-reads the Keychain (e.g. after the client refreshed a session or a sign-in finished).
    func reload() {
        let connection = try? credentials.load()
        summary = connection.map { connection in
            let usesAPIKey: Bool
            if case .apiKey = connection.credential { usesAPIKey = true } else { usesAPIKey = false }
            return Summary(baseURL: connection.baseURL, username: connection.username, usesAPIKey: usesAPIKey)
        }
    }

    func signIn(serverURL: URL, username: String, password: String) async throws {
        try await client.login(serverURL: serverURL, username: username, password: password)
        reload()
        ABSProgressReporter.connectionChanged(account: summary?.progressAccount)
        ABSProgressReporter.flush()
    }

    func connect(serverURL: URL, apiKey: String) async throws {
        try await client.connect(serverURL: serverURL, apiKey: apiKey)
        reload()
        ABSProgressReporter.connectionChanged(account: summary?.progressAccount)
        ABSProgressReporter.flush()
    }

    func disconnect() {
        ABSProgressReporter.connectionChanged(account: nil)
        try? credentials.clear()
        reload()
        // Cancel any in-flight token refresh so it cannot outlive this connection.
        Task { await client.invalidateRefresh() }
    }
}

/// The server and user an ABS progress report was recorded for.
nonisolated struct ABSProgressAccount: Equatable, Sendable {
    let server: String
    let username: String?
}

/// Persists only the latest token-free position per item before attempting delivery.
@MainActor
enum ABSProgressReporter {
    nonisolated private static let log = Logger(subsystem: "andreibaludev.Pageless", category: "ABSProgress")
    private struct Entry: Codable, Equatable {
        let server: String
        /// Nil only for entries saved before the outbox was scoped by user; those are dropped.
        let username: String?
        let itemID: String
        let currentTime: Double
        let duration: Double
        let isFinished: Bool
        let timestamp: Date

        var account: ABSProgressAccount { ABSProgressAccount(server: server, username: username) }
    }
    private static let key = "abs.progressOutbox"
    private static var entries: [String: Entry] = {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return saved
    }()
    private static var flushing = false

    private static func save() {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func connectionChanged(account: ABSProgressAccount?) {
        entries = entries.filter { $0.value.account == account }
        save()
    }

    static func pendingTimestamp(itemID: String) -> Date? {
        guard let entry = entries[itemID], entry.account == ABSAccount.shared.summary?.progressAccount else { return nil }
        return entry.timestamp
    }

    static func report(_ snapshot: ABSProgressSnapshot, client: AudiobookshelfClient? = nil) {
        guard let account = ABSAccount.shared.summary?.progressAccount else { return }
        entries[snapshot.itemID] = Entry(server: account.server, username: account.username, itemID: snapshot.itemID,
            currentTime: snapshot.currentTime, duration: snapshot.duration,
            isFinished: snapshot.isFinished, timestamp: .now)
        save()
        flush(client: client)
    }

    static func flush(client: AudiobookshelfClient? = nil) {
        guard !flushing, NetworkMonitor.shared.isConnected,
              let account = ABSAccount.shared.summary?.progressAccount else { return }
        connectionChanged(account: account)
        flushing = true
        let client = client ?? ABSAccount.shared.client
        Task {
            defer { flushing = false }
            var attempted: [String: Entry] = [:]
            while let entry = entries.values.first(where: { attempted[$0.itemID] != $0 }) {
                attempted[entry.itemID] = entry
                do {
                    if let progress = try await client.mediaProgress(itemID: entry.itemID),
                       let lastUpdate = progress.lastUpdate,
                       Date(timeIntervalSince1970: lastUpdate / 1000) > entry.timestamp {
                        if entries[entry.itemID] == entry { entries.removeValue(forKey: entry.itemID); save() }
                        continue
                    }
                } catch {
                    log.info("Progress check failed: \(String(describing: error), privacy: .public)")
                    continue
                }
                var remove = false
                do {
                    try await client.updateProgress(itemID: entry.itemID,
                        update: ABSProgressUpdate(duration: entry.duration, currentTime: entry.currentTime,
                                                  isFinished: entry.isFinished), expectedAccount: entry.account)
                    remove = true
                } catch {
                    if case AudiobookshelfError.serverError(let status) = error,
                       (400..<500).contains(status), ![401, 408, 429].contains(status) { remove = true }
                    log.info("Progress delivery failed: \(String(describing: error), privacy: .public)")
                }
                if remove, entries[entry.itemID] == entry { entries.removeValue(forKey: entry.itemID); save() }
            }
        }
    }
}

/// A book-global position for one ABS item, derived from Unpaged's (track, time-in-track) pair.
nonisolated struct ABSProgressSnapshot: Equatable, Sendable {
    let itemID: String
    let currentTime: Double
    let duration: Double
    let isFinished: Bool

    var update: ABSProgressUpdate {
        ABSProgressUpdate(duration: duration, currentTime: currentTime, isFinished: isFinished)
    }
}
