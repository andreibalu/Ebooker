//
//  LibraryMutationTransaction.swift
//  Pageless
//

import Foundation
import OSLog
import SwiftData

enum LibraryMutationError: LocalizedError {
    case pathOutsideAudiobooks(URL)
    case invalidFolderName
    case invalidFileName
    case markerPersistenceFailed
    case modelCommittedButTransactionMarkerFailed(Error)
    case rollbackFailed(operationError: Error, rollbackError: Error)

    var errorDescription: String? {
        switch self {
        case .pathOutsideAudiobooks:
            "Library storage path is invalid."
        case .invalidFolderName:
            "Invalid audiobook storage folder name."
        case .invalidFileName:
            "Invalid audiobook file name."
        case .markerPersistenceFailed:
            "Library data committed, but cleanup marker could not be persisted."
        case .modelCommittedButTransactionMarkerFailed:
            "Library data committed, but transaction cleanup could not be recorded."
        case .rollbackFailed:
            "Library operation failed and rollback could not complete."
        }
    }

    var operationError: Error? {
        guard case LibraryMutationError.rollbackFailed(let operationError, _) = self else { return nil }
        return operationError
    }

    var rollbackError: Error? {
        guard case LibraryMutationError.rollbackFailed(_, let rollbackError) = self else { return nil }
        return rollbackError
    }
}

struct LibraryMutationRollbackError: LocalizedError {
    let errors: [Error]

    var errorDescription: String? {
        "Library rollback could not complete."
    }
}

struct LibraryMutationEnvironment {
    typealias FileOperation = (URL, URL) throws -> Void
    typealias RemoveOperation = (URL) throws -> Void
    typealias SaveOperation = (ModelContext) throws -> Void
    typealias WriteOperation = (Data, URL) throws -> Void

    let rootURL: URL?
    let fileManager: FileManager
    let copyItem: FileOperation
    let moveItem: FileOperation
    let removeItem: RemoveOperation
    let save: SaveOperation
    let writeData: WriteOperation

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default,
        copyItem: FileOperation? = nil,
        moveItem: FileOperation? = nil,
        removeItem: RemoveOperation? = nil,
        save: @escaping SaveOperation = { try $0.save() },
        writeData: WriteOperation? = nil
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.copyItem = copyItem ?? { source, destination in
            try fileManager.copyItem(at: source, to: destination)
        }
        self.moveItem = moveItem ?? { source, destination in
            try fileManager.moveItem(at: source, to: destination)
        }
        self.removeItem = removeItem ?? { url in
            try fileManager.removeItem(at: url)
        }
        self.save = save
        self.writeData = writeData ?? { data, url in
            try data.write(to: url, options: .atomic)
        }
    }

    static func live(rootURL: URL? = nil) -> LibraryMutationEnvironment {
        LibraryMutationEnvironment(rootURL: rootURL)
    }
}

/// Reversible filesystem transaction for audiobook storage.
///
/// Every transaction lives under `Audiobooks/.transactions`. New audio is copied into staging;
/// existing storage is moved to backup before promotion. Model saves happen outside this helper,
/// while callers use `rollback()` for pre-commit failures and `commit()` after a successful save.
final class LibraryMutationTransaction {
    private static let log = Logger(subsystem: "andreibaludev.Pageless", category: "LibraryMutation")
    let environment: LibraryMutationEnvironment
    let rootURL: URL
    let transactionURL: URL
    let stagingURL: URL
    let backupURL: URL
    private let committedMarkerURL: URL
    private var promotedTargetURL: URL?
    private var backups: [(target: URL, backup: URL)] = []
    private var didPromote = false
    private(set) var isCommitted = false

    init(rootURL suppliedRootURL: URL? = nil, environment: LibraryMutationEnvironment = .live()) throws {
        self.environment = environment
        let resolvedRoot = suppliedRootURL
            ?? environment.rootURL
            ?? Self.defaultAudiobooksRoot(using: environment.fileManager)
        let rootURL = resolvedRoot.standardizedFileURL
        self.rootURL = rootURL
        let transactionsRoot = rootURL.appendingPathComponent(".transactions", isDirectory: true)
        let id = UUID().uuidString
        self.transactionURL = transactionsRoot.appendingPathComponent(id, isDirectory: true)
        self.stagingURL = self.transactionURL.appendingPathComponent("staging", isDirectory: true)
        self.backupURL = self.transactionURL.appendingPathComponent("backup", isDirectory: true)
        self.committedMarkerURL = self.transactionURL.appendingPathComponent("committed", isDirectory: false)

        try environment.fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        try environment.fileManager.createDirectory(at: transactionsRoot, withIntermediateDirectories: true)
        Self.retryCommittedCleanup(in: transactionsRoot, environment: environment)
        try environment.fileManager.createDirectory(at: self.transactionURL, withIntermediateDirectories: true)
        try environment.fileManager.createDirectory(at: self.stagingURL, withIntermediateDirectories: true)
    }

    static func defaultAudiobooksRoot(using fileManager: FileManager = .default) -> URL {
        let applicationSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return applicationSupport.appendingPathComponent("Audiobooks", isDirectory: true)
    }

    static func folderURL(for folderName: String, rootURL: URL) throws -> URL {
        guard !folderName.isEmpty,
              folderName != ".transactions",
              folderName != ".",
              folderName != "..",
              !folderName.contains("/"),
              !folderName.contains("\\") else {
            throw LibraryMutationError.invalidFolderName
        }
        let root = rootURL.standardizedFileURL
        let folder = root.appendingPathComponent(folderName, isDirectory: true).standardizedFileURL
        guard folder.deletingLastPathComponent() == root else {
            throw LibraryMutationError.pathOutsideAudiobooks(folder)
        }
        return folder
    }

    static func fileURL(for fileName: String, in folderURL: URL, rootURL: URL) throws -> URL {
        let root = rootURL.standardizedFileURL
        let folder = folderURL.standardizedFileURL
        guard folder.deletingLastPathComponent() == root else {
            throw LibraryMutationError.pathOutsideAudiobooks(folder)
        }
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              !fileName.contains("/"),
              !fileName.contains("\\") else {
            throw LibraryMutationError.invalidFileName
        }

        let file = folder.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL
        guard file.deletingLastPathComponent() == folder else {
            throw LibraryMutationError.pathOutsideAudiobooks(file)
        }
        return file
    }

    func stageCopy(from sourceURL: URL, named fileName: String) throws -> URL {
        let destinationURL = stagingURL.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL
        guard destinationURL.deletingLastPathComponent() == stagingURL.standardizedFileURL else {
            throw LibraryMutationError.pathOutsideAudiobooks(destinationURL)
        }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        try environment.copyItem(sourceURL, destinationURL)
        return destinationURL
    }

    func backupExistingFolder(at originalTargetURL: URL) throws {
        try validateTarget(originalTargetURL)
        let target = originalTargetURL.standardizedFileURL
        guard environment.fileManager.fileExists(atPath: target.path(percentEncoded: false)) else { return }
        let backupURL = backups.isEmpty
            ? self.backupURL
            : transactionURL.appendingPathComponent("backup-\(backups.count)", isDirectory: true)
        try environment.moveItem(target, backupURL)
        backups.append((target: target, backup: backupURL))
    }

    func promoteStaging(to targetURL: URL) throws {
        try validateTarget(targetURL)
        let target = targetURL.standardizedFileURL
        guard !environment.fileManager.fileExists(atPath: target.path(percentEncoded: false)) else {
            throw CocoaError(.fileWriteFileExists)
        }
        promotedTargetURL = target
        try environment.moveItem(stagingURL, target)
        didPromote = true
    }

    func markCommitted() throws {
        let markerData = Data("committed".utf8)
        do {
            try environment.writeData(markerData, committedMarkerURL)
            guard environment.fileManager.fileExists(atPath: committedMarkerURL.path(percentEncoded: false)),
                  try Data(contentsOf: committedMarkerURL) == markerData else {
                throw LibraryMutationError.markerPersistenceFailed
            }
        } catch {
            // Keep a durable recovery classification even when the injected/live marker writer
            // fails. The caller still receives the persistence error; next initialization can
            // recognize and clean this post-save transaction instead of treating it as unknown.
            do {
                try markerData.write(to: committedMarkerURL, options: .atomic)
                guard environment.fileManager.fileExists(atPath: committedMarkerURL.path(percentEncoded: false)),
                      try Data(contentsOf: committedMarkerURL) == markerData else {
                    throw LibraryMutationError.markerPersistenceFailed
                }
            } catch {
                // Disk failure on both marker paths is surfaced below; caller must retain the
                // post-save error and arrange recovery rather than rolling back the model.
            }
            throw LibraryMutationError.markerPersistenceFailed
        }
        isCommitted = true
    }

    func cleanupCommitted() {
        guard isCommitted else { return }
        do {
            try environment.removeItem(transactionURL)
        } catch {
            Self.log.error("Committed library mutation cleanup deferred")
        }
    }

    func commit() throws {
        try markCommitted()
        cleanupCommitted()
    }

    func rollback() throws {
        guard !isCommitted else { return }
        var errors: [Error] = []

        if didPromote,
           let promotedTargetURL,
           environment.fileManager.fileExists(atPath: promotedTargetURL.path(percentEncoded: false)) {
            do { try environment.removeItem(promotedTargetURL) } catch { errors.append(error) }
        }

        for backup in backups.reversed() {
            guard environment.fileManager.fileExists(atPath: backup.backup.path(percentEncoded: false)) else { continue }
            do { try environment.moveItem(backup.backup, backup.target) } catch { errors.append(error) }
        }

        // Preserve every recovery artifact if any restore step failed. Removing the transaction
        // directory here could destroy the only remaining backup needed for a later retry.
        if errors.isEmpty {
            if environment.fileManager.fileExists(atPath: stagingURL.path(percentEncoded: false)) {
                do { try environment.removeItem(stagingURL) } catch { errors.append(error) }
            }
            if errors.isEmpty,
               environment.fileManager.fileExists(atPath: transactionURL.path(percentEncoded: false)) {
                do { try environment.removeItem(transactionURL) } catch { errors.append(error) }
            }
        }

        if !errors.isEmpty {
            throw LibraryMutationRollbackError(errors: errors)
        }
    }

    static func rollbackAndRethrow(
        _ operationError: Error,
        modelContext: ModelContext,
        transaction: LibraryMutationTransaction
    ) throws -> Never {
        modelContext.rollback()
        do {
            try transaction.rollback()
        } catch {
            throw LibraryMutationError.rollbackFailed(
                operationError: operationError,
                rollbackError: error
            )
        }
        throw operationError
    }

    private func validateTarget(_ url: URL) throws {
        let target = url.standardizedFileURL
        guard target.deletingLastPathComponent() == rootURL.standardizedFileURL else {
            throw LibraryMutationError.pathOutsideAudiobooks(target)
        }
    }

    private static func retryCommittedCleanup(
        in transactionsRoot: URL,
        environment: LibraryMutationEnvironment
    ) {
        guard let entries = try? environment.fileManager.contentsOfDirectory(
            at: transactionsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries {
            let marker = entry.appendingPathComponent("committed", isDirectory: false)
            guard environment.fileManager.fileExists(atPath: marker.path(percentEncoded: false)) else { continue }
            do {
                try environment.removeItem(entry)
            } catch {
                Self.log.error("Committed library mutation retry failed")
            }
        }
    }
}
