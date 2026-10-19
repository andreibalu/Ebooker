//
//  CloudAudioState.swift
//  Pageless
//

import Foundation

/// One audio file in the app's iCloud Drive container, as the metadata query (or the E2E fake)
/// reports it. Keys in a status map are `"<book folderName>/<storedFileName>"`.
nonisolated struct CloudAudioFileStatus: Equatable, Sendable {
    var size: Int64
    /// The whole file has reached iCloud.
    var isUploaded: Bool
    var uploadFraction: Double
    /// This device holds a local copy of the file's data.
    var isDownloaded: Bool
    var downloadFraction: Double
    var uploadError: CloudAudioUploadError?
}

nonisolated enum CloudAudioUploadError: Equatable, Sendable {
    case quotaExceeded
    case other
}

/// What iCloud holds of one book's audio. Only `.stored` promises that another device, or this
/// one after a reinstall, can download the whole book.
nonisolated enum CloudAudioState: Equatable, Sendable {
    /// No file of this book is in iCloud.
    case none
    /// Files are on their way up. The fraction counts files still being copied in as zero.
    case uploading(fraction: Double)
    /// Every track's file is in iCloud and fully uploaded.
    case stored
    /// Some track files are in iCloud and others are missing, with nothing copying them here.
    case partial
    case quotaExceeded
    case failed

    static func derive(
        folderName: String,
        trackFileNames: [String],
        files: [String: CloudAudioFileStatus],
        isCopying: Bool
    ) -> CloudAudioState {
        guard !trackFileNames.isEmpty else { return .none }
        let statuses = trackFileNames.map { files[CloudAudioPlan.key(folderName, $0)] }
        let present = statuses.compactMap { $0 }
        if present.isEmpty { return isCopying ? .uploading(fraction: 0) : .none }

        if present.contains(where: { $0.uploadError == .quotaExceeded }) { return .quotaExceeded }
        if present.contains(where: { $0.uploadError == .other }) { return .failed }

        let isComplete = present.count == statuses.count
        if isComplete && present.allSatisfy(\.isUploaded) { return .stored }
        if !isComplete && !isCopying && present.allSatisfy(\.isUploaded) { return .partial }

        // Weight by size so one long file doesn't read as done because short ones are; a file not
        // yet copied in counts at the average known size.
        let knownSizes = present.map { max($0.size, 1) }
        let averageSize = knownSizes.reduce(0, +) / Int64(knownSizes.count)
        var done = 0.0
        var total = 0.0
        for status in statuses {
            guard let status else {
                total += Double(averageSize)
                continue
            }
            let size = Double(max(status.size, 1))
            total += size
            done += size * (status.isUploaded ? 1 : min(max(status.uploadFraction, 0), 1))
        }
        return .uploading(fraction: total > 0 ? done / total : 0)
    }
}

/// Which files an upload touches. Pure so the cross-device rules stay testable.
nonisolated enum CloudAudioPlan {
    static func key(_ folderName: String, _ fileName: String) -> String {
        "\(folderName)/\(fileName)"
    }

    /// Track files with no copy in iCloud yet. Resuming an upload never overwrites or deletes: another
    /// device may be uploading a newer copy of the same book right now.
    static func filesToCopy(
        folderName: String,
        trackFileNames: [String],
        files: [String: CloudAudioFileStatus]
    ) -> [String] {
        trackFileNames.filter { files[key(folderName, $0)] == nil }
    }
}
