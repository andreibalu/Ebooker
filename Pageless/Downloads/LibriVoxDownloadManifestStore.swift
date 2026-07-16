//
//  LibriVoxDownloadManifestStore.swift
//  Pageless
//

import Foundation

enum LibriVoxDownloadManifestStoreError: LocalizedError {
    case corrupted(URL, Error)
    case unreadable(URL, Error)
    case invalidJob(URL, String)

    var errorDescription: String? {
        switch self {
        case .corrupted(let url, let error):
            "Corrupt LibriVox download manifest \(url.lastPathComponent): \(error.localizedDescription)"
        case .unreadable(let url, let error):
            "Unreadable LibriVox download manifest \(url.lastPathComponent): \(error.localizedDescription)"
        case .invalidJob(let url, let reason):
            "Invalid LibriVox download manifest \(url.lastPathComponent): \(reason)"
        }
    }
}

final class LibriVoxDownloadManifestStore: @unchecked Sendable {
    let rootURL: URL
    let manifestsURL: URL
    let corruptURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        rootURL: URL = LibriVoxDownloadManifestStore.defaultRootURL(),
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        manifestsURL = rootURL.appendingPathComponent("Manifests", isDirectory: true)
        corruptURL = rootURL.appendingPathComponent("Corrupt", isDirectory: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func loadAll() throws -> [LibriVoxDownloadJob] {
        try prepareDirectories()
        var jobs: [LibriVoxDownloadJob] = []
        for fileURL in try manifestFiles() {
            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                throw LibriVoxDownloadManifestStoreError.unreadable(fileURL, error)
            }
            do {
                let job = try decoder.decode(LibriVoxDownloadJob.self, from: data)
                try validate(job, fileURL: fileURL)
                jobs.append(job)
            } catch {
                do {
                    try quarantine(fileURL)
                } catch {
                    throw LibriVoxDownloadManifestStoreError.unreadable(fileURL, error)
                }
            }
        }
        return jobs.sorted {
            if $0.catalogID == $1.catalogID {
                return $0.attemptID.uuidString < $1.attemptID.uuidString
            }
            return $0.catalogID < $1.catalogID
        }
    }

    func save(_ job: LibriVoxDownloadJob) throws {
        try validate(job, fileURL: manifestURL(for: job.attemptID))
        try prepareDirectories()
        let destinationURL = manifestURL(for: job.attemptID)
        let temporaryURL = manifestsURL.appendingPathComponent(
            ".\(job.attemptID.uuidString).\(UUID().uuidString).tmp"
        )
        try encoder.encode(job).write(to: temporaryURL, options: .atomic)
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    func delete(attemptID: UUID) throws {
        let fileURL = manifestURL(for: attemptID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    func manifestFiles() throws -> [URL] {
        try prepareDirectories()
        return try fileManager.contentsOfDirectory(
            at: manifestsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func quarantinedFiles() throws -> [URL] {
        try prepareDirectories()
        return try fileManager.contentsOfDirectory(
            at: corruptURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func manifestURL(for attemptID: UUID) -> URL {
        manifestsURL.appendingPathComponent("\(attemptID.uuidString).json")
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(at: manifestsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: corruptURL, withIntermediateDirectories: true)
    }

    private func validate(_ job: LibriVoxDownloadJob, fileURL: URL) throws {
        guard !job.catalogID.isEmpty else {
            throw LibriVoxDownloadManifestStoreError.invalidJob(fileURL, "empty catalog ID")
        }
        guard fileURL.deletingPathExtension().lastPathComponent == job.attemptID.uuidString else {
            throw LibriVoxDownloadManifestStoreError.invalidJob(fileURL, "manifest attempt identity mismatch")
        }
        guard isContainedPathComponent(job.stagingFolderName, under: rootURL) else {
            throw LibriVoxDownloadManifestStoreError.invalidJob(fileURL, "unsafe staging folder")
        }
        if let destinationFolderName = job.destinationFolderName,
           !isContainedPathComponent(destinationFolderName, under: rootURL) {
            throw LibriVoxDownloadManifestStoreError.invalidJob(fileURL, "unsafe destination folder")
        }
        if let backupFolderName = job.backupFolderName,
           !isContainedPathComponent(backupFolderName, under: rootURL) {
            throw LibriVoxDownloadManifestStoreError.invalidJob(fileURL, "unsafe backup folder")
        }
        guard !job.tracks.isEmpty else {
            throw LibriVoxDownloadManifestStoreError.invalidJob(fileURL, "empty track list")
        }
        guard job.tracks.enumerated().allSatisfy({ index, track in
            track.orderIndex == index
                && ["http", "https"].contains(track.remoteURL.scheme?.lowercased())
                && !(track.remoteURL.host?.isEmpty ?? true)
                && track.durationSeconds.isFinite
                && track.durationSeconds > 0
        }) else {
            throw LibriVoxDownloadManifestStoreError.invalidJob(
                fileURL,
                "invalid track URL, duration, or contiguous order"
            )
        }
        let names = job.tracks.map(\.storedFileName)
        guard Set(names).count == job.tracks.count,
              job.tracks.allSatisfy({ isContainedPathComponent($0.storedFileName, under: rootURL) })
        else {
            throw LibriVoxDownloadManifestStoreError.invalidJob(fileURL, "duplicate or invalid track shape")
        }
        guard job.completedIndexes.allSatisfy({ $0 >= 0 && $0 < job.tracks.count }) else {
            throw LibriVoxDownloadManifestStoreError.invalidJob(fileURL, "completed track index out of bounds")
        }
        guard job.fileMetadata.keys.allSatisfy({ job.completedIndexes.contains($0) }),
              job.fileMetadata.values.allSatisfy({ $0.byteCount > 0 && $0.sha256.count == 64 })
        else {
            throw LibriVoxDownloadManifestStoreError.invalidJob(fileURL, "invalid staged file metadata")
        }
        if job.phase == .finalizing {
            guard Set(job.fileMetadata.keys) == Set(job.tracks.indices) else {
                throw LibriVoxDownloadManifestStoreError.invalidJob(
                    fileURL,
                    "finalizing manifest missing staged file metadata"
                )
            }
        }
    }

    private func isContainedPathComponent(_ value: String, under _: URL) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
    }

    private func quarantine(_ fileURL: URL) throws {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let destinationURL = corruptURL.appendingPathComponent(
            "\(stem)-\(UUID().uuidString).json"
        )
        try fileManager.moveItem(at: fileURL, to: destinationURL)
    }

    private static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return applicationSupport.appendingPathComponent("DownloadJobs", isDirectory: true)
    }
}
