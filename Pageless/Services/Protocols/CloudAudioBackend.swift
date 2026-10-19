//
//  CloudAudioBackend.swift
//  Pageless
//

import Foundation

/// File operations on the app's iCloud Drive container, behind a protocol so DEBUG fixture
/// launches swap in a local folder. Every method except `startMonitoring` may block on file
/// coordination; call them off the main actor.
nonisolated protocol CloudAudioBackend: Sendable {
    /// The `Audiobooks` folder inside the ubiquity container, or nil when iCloud Drive is off for
    /// this account or this app.
    func audiobooksRoot() async -> URL?
    /// Copies a local file in, creating its folder. The destination must not exist.
    func copyIn(_ source: URL, to destination: URL) throws
    /// Deletes a file or folder from iCloud on every device.
    func remove(_ url: URL) throws
    func startDownloading(_ url: URL) throws
    /// Drops this device's local data for an uploaded file. iCloud keeps it.
    func evict(_ url: URL) throws
    /// Copies a downloaded file out of the container.
    func copyOut(_ source: URL, to destination: URL) throws
    @MainActor func startMonitoring(
        root: URL,
        onChange: @escaping @MainActor ([String: CloudAudioFileStatus]) -> Void
    ) -> CloudAudioMonitoring
}

@MainActor
protocol CloudAudioMonitoring: AnyObject {
    /// Asks for a fresh report soon, after this app changed the container.
    func refresh()
    func stop()
}
