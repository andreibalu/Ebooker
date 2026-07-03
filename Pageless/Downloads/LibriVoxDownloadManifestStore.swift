//
//  LibriVoxDownloadManifestStore.swift
//  Pageless
//

import Foundation

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
            do {
                jobs.append(try decoder.decode(
                    LibriVoxDownloadJob.self,
                    from: Data(contentsOf: fileURL)
                ))
            } catch {
                try quarantine(fileURL)
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
