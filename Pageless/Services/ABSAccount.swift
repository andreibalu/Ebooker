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
    }

    func connect(serverURL: URL, apiKey: String) async throws {
        try await client.connect(serverURL: serverURL, apiKey: apiKey)
        reload()
    }

    func disconnect() {
        try? credentials.clear()
        reload()
        // Cancel any in-flight token refresh so it cannot outlive this connection.
        Task { await client.invalidateRefresh() }
    }
}

/// Pushes listening position back to the server. Fire-and-forget: never awaited by playback,
/// failures are logged and dropped (the next flush point sends a newer position anyway).
@MainActor
enum ABSProgressReporter {
    nonisolated private static let log = Logger(subsystem: "andreibaludev.Pageless", category: "ABSProgress")

    static func report(_ snapshot: ABSProgressSnapshot, client: AudiobookshelfClient? = nil) {
        let client = client ?? ABSAccount.shared.client
        Task.detached(priority: .utility) {
            do {
                try await client.updateProgress(itemID: snapshot.itemID, update: snapshot.update)
            } catch {
                log.info("Progress push skipped: \(String(describing: error), privacy: .public)")
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
