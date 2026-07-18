//
//  LegacyFreeBookDownloadManifestStore.swift
//  Pageless
//

import Foundation

enum LegacyFreeBookDownloadManifestStoreError: LocalizedError {
    case corrupted(URL, Error)
    case unreadable(URL, Error)
    case invalidJob(String)

    var errorDescription: String? {
        switch self {
        case .corrupted(let url, let error):
            "Corrupt legacy download manifest \(url.lastPathComponent): \(error.localizedDescription)"
        case .unreadable(let url, let error):
            "Unreadable legacy download manifest \(url.lastPathComponent): \(error.localizedDescription)"
        case .invalidJob(let reason):
            "Invalid legacy download manifest: \(reason)"
        }
    }
}
final class LegacyFreeBookDownloadManifestStore: @unchecked Sendable {
    let rootURL: URL
    private let manifestsURL: URL
    private let corruptURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(
        rootURL: URL = LegacyFreeBookDownloadManifestStore.defaultRootURL(),
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        manifestsURL = rootURL.appendingPathComponent("Manifests", isDirectory: true)
        corruptURL = rootURL.appendingPathComponent("Corrupt", isDirectory: true)
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadAll() throws -> [LegacyFreeBookDownloadJob] {
        try prepareDirectories()
        var jobs: [LegacyFreeBookDownloadJob] = []
        for fileURL in try manifestFiles() {
            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                throw LegacyFreeBookDownloadManifestStoreError.unreadable(fileURL, error)
            }
            do {
                let job = try decoder.decode(LegacyFreeBookDownloadJob.self, from: data)
                try validate(job, fileURL: fileURL)
                jobs.append(job)
            } catch {
                do {
                    try quarantine(fileURL)
                } catch {
                    throw LegacyFreeBookDownloadManifestStoreError.unreadable(fileURL, error)
                }
            }
        }
        return jobs.sorted { $0.attemptID.uuidString < $1.attemptID.uuidString }
    }

    func save(_ job: LegacyFreeBookDownloadJob) throws {
        try validate(job)
        try prepareDirectories()
        let destination = manifestsURL.appendingPathComponent("\(job.attemptID.uuidString).json")
        let temporary = manifestsURL.appendingPathComponent(".\(UUID().uuidString).tmp")
        try encoder.encode(job).write(to: temporary, options: .atomic)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    func delete(attemptID: UUID) throws {
        let fileURL = manifestsURL.appendingPathComponent("\(attemptID.uuidString).json")
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

    private func prepareDirectories() throws {
        try fileManager.createDirectory(at: manifestsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: corruptURL, withIntermediateDirectories: true)
    }

    private func validate(_ job: LegacyFreeBookDownloadJob, fileURL: URL? = nil) throws {
        guard !job.catalogID.isEmpty,
              isSafePathComponent(job.folderName),
              !job.catalogEntry.tracks.isEmpty
        else { throw LegacyFreeBookDownloadManifestStoreError.invalidJob("missing book metadata, folder, or tracks") }
        if let fileURL,
           fileURL.deletingPathExtension().lastPathComponent != job.attemptID.uuidString {
            throw LegacyFreeBookDownloadManifestStoreError.invalidJob("manifest attempt identity mismatch")
        }
        let indexes = job.catalogEntry.tracks.map(\.orderIndex)
        let names = job.catalogEntry.tracks.map(\.fileName)
        let expectedIndexes = Array(0..<job.catalogEntry.tracks.count)
        guard indexes == expectedIndexes,
              Set(names).count == names.count,
              job.catalogEntry.tracks.allSatisfy({ isSafePathComponent($0.fileName) }),
              job.completedIndexes.allSatisfy({ indexes.contains($0) })
        else { throw LegacyFreeBookDownloadManifestStoreError.invalidJob("duplicate or invalid track shape") }
        guard job.catalogEntry.tracks.allSatisfy({ track in
            guard let url = URL(string: track.downloadURL),
                  ["http", "https"].contains(url.scheme?.lowercased()),
                  !(url.host?.isEmpty ?? true) else { return false }
            return track.durationSeconds.isFinite && track.durationSeconds > 0
        }) else {
            throw LegacyFreeBookDownloadManifestStoreError.invalidJob("invalid track URL or duration")
        }
    }

    private func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
    }

    private func quarantine(_ fileURL: URL) throws {
        let destination = corruptURL.appendingPathComponent(
            "\(fileURL.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).json"
        )
        try fileManager.moveItem(at: fileURL, to: destination)
    }

    private static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return support.appendingPathComponent("LegacyFreeBookDownloadJobs", isDirectory: true)
    }
}
