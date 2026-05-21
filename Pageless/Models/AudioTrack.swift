//
//  AudioTrack.swift
//  Pageless
//

import Foundation
import SwiftData

@Model
final class AudioTrack: Identifiable {
    // CloudKit-backed SwiftData stores cannot declare @Attribute(.unique);
    // app-level UUID uniqueness is enforced by `id` semantics.
    var id: UUID = UUID()
    var title: String = ""
    var originalFileName: String = ""
    var storedFileName: String = ""
    var orderIndex: Int = 0
    var duration: Double = 0
    var audiobook: Audiobook?

    // Nullable for lightweight migration (same pattern as Audiobook._isFreeBook).
    private var _remoteURLString: String?

    var remoteURLString: String? {
        get { _remoteURLString }
        set { _remoteURLString = newValue }
    }

    var remoteURL: URL? {
        guard let s = _remoteURLString, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    // SHA-256 hex digest of a content snapshot (first 1MB || last 1MB || filesize || durationMs).
    // Used to auto-match this track to a cloud-synced Audiobook when the user re-imports the same
    // file after a reinstall or on a new device. Nullable for lightweight migration and because
    // streaming-only tracks have no local file to hash.
    private var _contentFingerprint: String?
    var contentFingerprint: String? {
        get { _contentFingerprint }
        set { _contentFingerprint = newValue }
    }

    init(
        title: String,
        originalFileName: String,
        storedFileName: String,
        orderIndex: Int,
        duration: Double,
        audiobook: Audiobook? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
        self.orderIndex = orderIndex
        self.duration = duration
        self.audiobook = audiobook
    }
}
