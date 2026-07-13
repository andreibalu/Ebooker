//
//  LibraryImportMutationTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

@MainActor
struct LibraryImportMutationTests {
    @Test func importCopyFailureLeavesNoPartialBookOrStorage() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSourceFile(in: root, name: "chapter.m4a")
        let pending = makePending(source: source)
        let (container, context) = try makeContainerAndContext()
        let environment = makeEnvironment(root: root, copyError: .copy)

        do {
            _ = try LibraryImportService.importAudiobook(
                from: pending,
                title: "Book",
                author: "Author",
                modelContext: context,
                mutationEnvironment: environment
            )
            Issue.record("Expected copy failure")
        } catch MutationTestError.copy {
            // Expected RED behavior target.
        }

        let refetched = ModelContext(container)
        #expect(try refetched.fetch(FetchDescriptor<Audiobook>()).isEmpty)
        #expect(try transactionEntries(in: root).isEmpty)
    }

    @Test func importSaveFailureLeavesNoRefetchableBookOrStorage() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSourceFile(in: root, name: "chapter.m4a")
        let pending = makePending(source: source)
        let (container, context) = try makeContainerAndContext()
        let environment = makeEnvironment(root: root, saveError: .save)

        do {
            _ = try LibraryImportService.importAudiobook(
                from: pending,
                title: "Book",
                author: "Author",
                modelContext: context,
                mutationEnvironment: environment
            )
            Issue.record("Expected save failure")
        } catch MutationTestError.save {
            // Expected RED behavior target.
        }

        let refetched = ModelContext(container)
        #expect(try refetched.fetch(FetchDescriptor<Audiobook>()).isEmpty)
        #expect(try transactionEntries(in: root).isEmpty)
    }

    @Test func importPromoteFailureLeavesNoPartialBookOrStorage() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSourceFile(in: root, name: "chapter.m4a")
        let pending = makePending(source: source)
        let (container, context) = try makeContainerAndContext()
        let environment = makeEnvironment(root: root, moveError: .promote)

        do {
            _ = try LibraryImportService.importAudiobook(
                from: pending,
                title: "Book",
                author: "Author",
                modelContext: context,
                mutationEnvironment: environment
            )
            Issue.record("Expected promote failure")
        } catch MutationTestError.promote {
            // Expected RED behavior target.
        }

        let refetched = ModelContext(container)
        #expect(try refetched.fetch(FetchDescriptor<Audiobook>()).isEmpty)
        #expect(try transactionEntries(in: root).isEmpty)
    }

    @Test func hardDeleteSaveFailureRestoresFolderAndModel() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (container, context) = try makeContainerAndContext()
        let folderName = "delete-\(UUID().uuidString)"
        let book = makeBook(in: context, folderName: folderName, isDownloaded: true)
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: folder.appendingPathComponent("001-chapter.m4a"))
        try context.save()
        let environment = makeEnvironment(root: root, saveError: .save)

        do {
            try LibraryImportService.deleteAudiobook(
                book,
                deleteFiles: true,
                modelContext: context,
                mutationEnvironment: environment
            )
            Issue.record("Expected save failure")
        } catch MutationTestError.save {
            // Expected RED behavior target.
        }

        let refetched = ModelContext(container)
        #expect(try refetched.fetch(FetchDescriptor<Audiobook>()).contains { $0.id == book.id })
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("001-chapter.m4a").path))
    }

    @Test func softDeleteSaveFailureRestoresDownloadedStateAndFolder() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (container, context) = try makeContainerAndContext()
        let folderName = "soft-\(UUID().uuidString)"
        let book = makeBook(in: context, folderName: folderName, isDownloaded: true)
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: folder.appendingPathComponent("001-chapter.m4a"))
        try context.save()
        let environment = makeEnvironment(root: root, saveError: .save)

        do {
            try LibraryImportService.softDeleteAudiobook(book, modelContext: context, mutationEnvironment: environment)
            Issue.record("Expected save failure")
        } catch MutationTestError.save {
            // Expected RED behavior target.
        }

        let refetched = ModelContext(container)
        #expect(try refetched.fetch(FetchDescriptor<Audiobook>()).first { $0.id == book.id }?.isDownloaded == true)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("001-chapter.m4a").path))
    }

    @Test func archiveSaveFailureRestoresFreeBookStateAndFolder() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (container, context) = try makeContainerAndContext()
        let folderName = "archive-\(UUID().uuidString)"
        let book = makeBook(in: context, folderName: folderName, isDownloaded: true)
        book.isFreeBook = true
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: folder.appendingPathComponent("001-chapter.m4a"))
        try context.save()
        let environment = makeEnvironment(root: root, saveError: .save)

        do {
            try LibraryImportService.archiveFreeBook(book, modelContext: context, mutationEnvironment: environment)
            Issue.record("Expected save failure")
        } catch MutationTestError.save {
            // Expected RED behavior target.
        }

        let refetched = ModelContext(container)
        let restored = try refetched.fetch(FetchDescriptor<Audiobook>()).first { $0.id == book.id }
        #expect(restored?.isDownloaded == true)
        #expect(restored?.isArchived == false)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("001-chapter.m4a").path))
    }

    @Test func orphanAdoptionSaveFailureRestoresOldFolderAndTrackTopology() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (container, context) = try makeContainerAndContext()
        let folderName = "orphan-\(UUID().uuidString)"
        let book = makeBook(in: context, folderName: folderName, isDownloaded: false)
        book.tracks[0].contentFingerprint = "old"
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("old-audio".utf8).write(to: folder.appendingPathComponent("001-chapter.m4a"))
        try context.save()
        let source = try makeSourceFile(in: root, name: "new-chapter.m4a")
        let pending = makePending(source: source, fingerprint: "new")
        let environment = makeEnvironment(root: root, saveError: .save)

        do {
            _ = try OrphanRestoreService.adopt(
                orphan: book,
                pending: pending,
                modelContext: context,
                mutationEnvironment: environment
            )
            Issue.record("Expected save failure")
        } catch MutationTestError.save {
            // Expected RED behavior target.
        }

        let refetched = ModelContext(container)
        let restored = try refetched.fetch(FetchDescriptor<Audiobook>()).first { $0.id == book.id }
        #expect(restored?.isDownloaded == false)
        #expect(restored?.tracks.count == 1)
        #expect(restored?.tracks[0].contentFingerprint == "old")
        #expect(String(data: try Data(contentsOf: folder.appendingPathComponent("001-chapter.m4a")), encoding: .utf8) == "old-audio")
    }

    @Test func committedCleanupFailureLeavesRetryableDebrisThenNextTransactionCleansIt() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = makeEnvironment(root: root, removeError: .cleanup)
        let transaction = try LibraryMutationTransaction(rootURL: root, environment: first)
        try transaction.markCommitted()
        transaction.cleanupCommitted()

        #expect(!(try transactionEntries(in: root)).isEmpty)

        let retry = try LibraryMutationTransaction(rootURL: root, environment: .live(rootURL: root))
        try retry.rollback()
        #expect(try transactionEntries(in: root).isEmpty)
    }

    @Test func committedModelSurvivesCleanupFailureAndFreshInitializationRetriesIt() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSourceFile(in: root, name: "chapter.m4a")
        let (container, context) = try makeContainerAndContext()
        let environment = makeEnvironment(root: root, removeOnceError: .cleanup)

        let book = try LibraryImportService.importAudiobook(
            from: makePending(source: source),
            title: "Book",
            author: "Author",
            modelContext: context,
            mutationEnvironment: environment
        )

        let refetched = ModelContext(container)
        #expect(try refetched.fetch(FetchDescriptor<Audiobook>()).contains { $0.id == book.id })
        #expect(!(try transactionEntries(in: root)).isEmpty)

        let retry = try LibraryMutationTransaction(rootURL: root, environment: .live(rootURL: root))
        try retry.rollback()
        #expect(try transactionEntries(in: root).isEmpty)
    }

    @Test func markerWriteFailureDoesNotSilentlyReportSuccessOrRollbackCommittedModel() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSourceFile(in: root, name: "chapter.m4a")
        let (container, context) = try makeContainerAndContext()
        let environment = makeEnvironment(
            root: root,
            removeOnceError: .cleanup,
            writeError: .marker
        )

        do {
            _ = try LibraryImportService.importAudiobook(
                from: makePending(source: source),
                title: "Book",
                author: "Author",
                modelContext: context,
                mutationEnvironment: environment
            )
            Issue.record("Expected marker persistence failure")
        } catch let error as LibraryMutationError {
            guard case LibraryMutationError.modelCommittedButTransactionMarkerFailed = error else {
                Issue.record("Expected model-committed marker failure, got \(error)")
                return
            }
        }

        let refetched = ModelContext(container)
        #expect(try refetched.fetch(FetchDescriptor<Audiobook>()).count == 1)
        let entries = try transactionEntries(in: root)
        #expect(entries.count == 1)
        #expect(FileManager.default.fileExists(atPath: entries[0].appendingPathComponent("committed").path(percentEncoded: false)))

        let retryDuringCleanupFailure = try LibraryMutationTransaction(rootURL: root, environment: environment)
        try retryDuringCleanupFailure.rollback()
        #expect(!(try transactionEntries(in: root)).isEmpty)

        let retry = try LibraryMutationTransaction(rootURL: root, environment: .live(rootURL: root))
        try retry.rollback()
        #expect(try transactionEntries(in: root).isEmpty)
    }

    @Test func rollbackFailurePreservesOperationAndRollbackErrors() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSourceFile(in: root, name: "chapter.m4a")
        let (container, context) = try makeContainerAndContext()
        let environment = makeEnvironment(root: root, saveError: .save, removeError: .rollback)

        do {
            _ = try LibraryImportService.importAudiobook(
                from: makePending(source: source),
                title: "Book",
                author: "Author",
                modelContext: context,
                mutationEnvironment: environment
            )
            Issue.record("Expected combined rollback failure")
        } catch let error as LibraryMutationError {
            guard case LibraryMutationError.rollbackFailed(let operationError, let rollbackError) = error else {
                Issue.record("Expected rollbackFailed, got \(error)")
                return
            }
            #expect(operationError is MutationTestError)
            #expect(rollbackError is LibraryMutationRollbackError)
            #expect((rollbackError as? LibraryMutationRollbackError)?.errors.isEmpty == false)
        }

        let refetched = ModelContext(container)
        #expect(try refetched.fetch(FetchDescriptor<Audiobook>()).isEmpty)
    }

    @Test func failedBackupRestorePreservesTransactionAndBackupForRetry() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (container, context) = try makeContainerAndContext()
        let folderName = "restore-failure-\(UUID().uuidString)"
        let book = makeBook(in: context, folderName: folderName, isDownloaded: true)
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: folder.appendingPathComponent("001-chapter.m4a"))
        try context.save()

        let fileManager = FileManager.default
        var moveCalls = 0
        let environment = LibraryMutationEnvironment(
            rootURL: root,
            moveItem: { source, destination in
                moveCalls += 1
                if moveCalls == 2 { throw MutationTestError.rollback }
                try fileManager.moveItem(at: source, to: destination)
            },
            save: { _ in throw MutationTestError.save }
        )

        do {
            try LibraryImportService.softDeleteAudiobook(
                book,
                modelContext: context,
                mutationEnvironment: environment
            )
            Issue.record("Expected combined rollback failure")
        } catch let error as LibraryMutationError {
            guard case LibraryMutationError.rollbackFailed(_, let rollbackError) = error else {
                Issue.record("Expected rollbackFailed, got \(error)")
                return
            }
            #expect(rollbackError is LibraryMutationRollbackError)
        }

        let refetched = ModelContext(container)
        #expect(try refetched.fetch(FetchDescriptor<Audiobook>()).first { $0.id == book.id }?.isDownloaded == true)
        let entries = try transactionEntries(in: root)
        #expect(entries.count == 1)
        let backup = entries[0].appendingPathComponent("backup", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: backup.appendingPathComponent("001-chapter.m4a").path(percentEncoded: false)))
    }

    @Test func invalidStoragePathErrorUsesGenericUserFacingText() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let transaction = try LibraryMutationTransaction(rootURL: root, environment: .live(rootURL: root))
        let outside = root.deletingLastPathComponent().appendingPathComponent("sensitive-audiobook-path")

        do {
            try transaction.promoteStaging(to: outside)
            Issue.record("Expected path validation failure")
        } catch let error as LibraryMutationError {
            let description = error.localizedDescription
            #expect(description == "Library storage path is invalid.")
            #expect(!description.contains(root.path))
            #expect(!description.contains(outside.path))
        }
    }

    @Test func persistedFolderTraversalIsRejectedBeforeMergeSourceAccess() throws {
        let book = Audiobook(title: "Book", folderName: "../outside", isDownloaded: true)
        let track = AudioTrack(
            title: "Chapter",
            originalFileName: "chapter.m4a",
            storedFileName: "chapter.m4a",
            orderIndex: 0,
            duration: 60,
            audiobook: book
        )

        do {
            _ = try LibraryImportService.fileURL(for: track, in: book)
            Issue.record("Expected persisted folder traversal rejection")
        } catch LibraryMutationError.pathOutsideAudiobooks {
            // Expected.
        }
    }

    @Test func persistedStoredFileTraversalIsRejectedBeforeMergeSourceAccess() throws {
        let book = Audiobook(title: "Book", folderName: UUID().uuidString, isDownloaded: true)
        let track = AudioTrack(
            title: "Chapter",
            originalFileName: "chapter.m4a",
            storedFileName: "../outside.m4a",
            orderIndex: 0,
            duration: 60,
            audiobook: book
        )

        do {
            _ = try LibraryImportService.fileURL(for: track, in: book)
            Issue.record("Expected persisted file traversal rejection")
        } catch LibraryMutationError.invalidFileName {
            // Expected.
        }
    }

    @Test func orphanAdoptionCopyFailureLeavesPersistedOrphanUntouched() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (container, context) = try makeContainerAndContext()
        let folderName = "orphan-copy-\(UUID().uuidString)"
        let book = makeBook(in: context, folderName: folderName, isDownloaded: false)
        book.tracks[0].contentFingerprint = "old"
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("old-audio".utf8).write(to: folder.appendingPathComponent("001-chapter.m4a"))
        try context.save()
        let source = try makeSourceFile(in: root, name: "new-chapter.m4a")

        do {
            _ = try OrphanRestoreService.adopt(
                orphan: book,
                pending: makePending(source: source, fingerprint: "new"),
                modelContext: context,
                mutationEnvironment: makeEnvironment(root: root, copyError: .copy)
            )
            Issue.record("Expected copy failure")
        } catch MutationTestError.copy {
            // Expected.
        }

        let refetched = ModelContext(container)
        let restored = try refetched.fetch(FetchDescriptor<Audiobook>()).first { $0.id == book.id }
        #expect(restored?.isDownloaded == false)
        #expect(restored?.tracks.first?.contentFingerprint == "old")
        #expect(String(data: try Data(contentsOf: folder.appendingPathComponent("001-chapter.m4a")), encoding: .utf8) == "old-audio")
    }

    @Test func orphanAdoptionPromoteFailureLeavesPersistedOrphanUntouched() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (container, context) = try makeContainerAndContext()
        let folderName = "orphan-promote-\(UUID().uuidString)"
        let book = makeBook(in: context, folderName: folderName, isDownloaded: false)
        book.tracks[0].contentFingerprint = "old"
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("old-audio".utf8).write(to: folder.appendingPathComponent("001-chapter.m4a"))
        try context.save()
        let source = try makeSourceFile(in: root, name: "new-chapter.m4a")

        do {
            _ = try OrphanRestoreService.adopt(
                orphan: book,
                pending: makePending(source: source, fingerprint: "new"),
                modelContext: context,
                mutationEnvironment: makeEnvironment(root: root, moveError: .promote, moveErrorOnCall: 2)
            )
            Issue.record("Expected promote failure")
        } catch MutationTestError.promote {
            // Expected.
        }

        let refetched = ModelContext(container)
        let restored = try refetched.fetch(FetchDescriptor<Audiobook>()).first { $0.id == book.id }
        #expect(restored?.isDownloaded == false)
        #expect(restored?.tracks.first?.contentFingerprint == "old")
        #expect(String(data: try Data(contentsOf: folder.appendingPathComponent("001-chapter.m4a")), encoding: .utf8) == "old-audio")
    }

    @Test func successfulImportLeavesNoTransactionDebris() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSourceFile(in: root, name: "chapter.m4a")
        let context = try makeContext()
        let pending = makePending(source: source)

        _ = try LibraryImportService.importAudiobook(
            from: pending,
            title: "Book",
            author: "Author",
            modelContext: context,
            mutationEnvironment: .live(rootURL: root)
        )

        #expect(try transactionEntries(in: root).isEmpty)
    }

    private enum MutationTestError: Error {
        case copy
        case promote
        case save
        case cleanup
        case marker
        case rollback
    }

    private func makeEnvironment(
        root: URL,
        copyError: MutationTestError? = nil,
        moveError: MutationTestError? = nil,
        moveErrorOnCall: Int? = nil,
        saveError: MutationTestError? = nil,
        removeError: MutationTestError? = nil,
        removeOnceError: MutationTestError? = nil,
        writeError: MutationTestError? = nil
    ) -> LibraryMutationEnvironment {
        let fileManager = FileManager.default
        var didFailRemoveOnce = false
        var moveCalls = 0
        return LibraryMutationEnvironment(
            rootURL: root,
            fileManager: fileManager,
            copyItem: { source, destination in
                if let copyError { throw copyError }
                try fileManager.copyItem(at: source, to: destination)
            },
            moveItem: { source, destination in
                moveCalls += 1
                if let moveError, moveErrorOnCall == nil || moveErrorOnCall == moveCalls {
                    throw moveError
                }
                try fileManager.moveItem(at: source, to: destination)
            },
            removeItem: { url in
                if !didFailRemoveOnce, let removeOnceError {
                    didFailRemoveOnce = true
                    throw removeOnceError
                }
                if let removeError { throw removeError }
                try fileManager.removeItem(at: url)
            },
            save: { context in
                if let saveError { throw saveError }
                try context.save()
            },
            writeData: { data, url in
                if let writeError { throw writeError }
                try data.write(to: url, options: .atomic)
            }
        )
    }

    private func makeContext() throws -> ModelContext {
        try makeContainerAndContext().1
    }

    private func makeContainerAndContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, ReadingSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, ModelContext(container))
    }

    @discardableResult
    private func makeBook(in context: ModelContext, folderName: String, isDownloaded: Bool) -> Audiobook {
        let book = Audiobook(title: "Book", folderName: folderName, isDownloaded: isDownloaded)
        let track = AudioTrack(
            title: "Chapter 1",
            originalFileName: "chapter.m4a",
            storedFileName: "001-chapter.m4a",
            orderIndex: 0,
            duration: 60,
            audiobook: book
        )
        book.tracks.append(track)
        context.insert(book)
        context.insert(track)
        return book
    }

    private func makePending(source: URL, fingerprint: String = "new") -> PendingImportSelection {
        let track = TrackImportPreview(
            sourceURL: source,
            title: "Chapter 1",
            originalFileName: source.lastPathComponent,
            duration: 60,
            contentFingerprint: fingerprint
        )
        return PendingImportSelection(
            sourceURLs: [source],
            suggestedTitle: "Book",
            suggestedAuthor: "",
            coverArtData: nil,
            tracks: [track]
        )
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("library-mutation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeSourceFile(in root: URL, name: String) throws -> URL {
        let source = root.appendingPathComponent(name)
        try Data("new-audio".utf8).write(to: source)
        return source
    }

    private func transactionEntries(in root: URL) throws -> [URL] {
        let transactions = root.appendingPathComponent(".transactions", isDirectory: true)
        guard FileManager.default.fileExists(atPath: transactions.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: transactions, includingPropertiesForKeys: nil)
    }
}
