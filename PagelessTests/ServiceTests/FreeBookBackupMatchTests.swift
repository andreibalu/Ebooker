//
//  FreeBookBackupMatchTests.swift
//  PagelessTests
//

import Testing
import Foundation
import SwiftData
@testable import Pageless

/// Covers free-book backup matching by catalog id: the analogue of own books' fingerprint match.
/// A removed free book is archived (kept in iCloud); re-adding it by id should find and restore it.
struct FreeBookBackupMatchTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, ReadingSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, ModelContext(container))
    }

    @Test func fetchFreeBackupFindsArchivedMatch() throws {
        let (container, context) = try makeContext()
        _ = container
        let backup = Audiobook(title: "Moby Dick", folderName: "a", isFreeBook: true, catalogId: "lv-123", isDownloaded: false)
        backup.isArchived = true
        context.insert(backup)
        try context.save()

        let found = OrphanRestoreService.fetchFreeBackup(catalogId: "lv-123", modelContext: context)
        #expect(found?.id == backup.id)
    }

    @Test func fetchFreeBackupIgnoresActiveAndUnrelated() throws {
        let (container, context) = try makeContext()
        _ = container
        // Active (not archived) free book with the same id — must NOT be treated as a backup.
        let active = Audiobook(title: "Active", folderName: "a", isFreeBook: true, catalogId: "lv-123", isDownloaded: false)
        // Archived free book with a different id.
        let other = Audiobook(title: "Other", folderName: "b", isFreeBook: true, catalogId: "lv-999", isDownloaded: false)
        other.isArchived = true
        // Archived own book (no catalog id).
        let own = Audiobook(title: "Own", folderName: "c", isDownloaded: false)
        own.isArchived = true
        [active, other, own].forEach { context.insert($0) }
        try context.save()

        #expect(OrphanRestoreService.fetchFreeBackup(catalogId: "lv-123", modelContext: context) == nil)
    }

    @Test func restoreFreeBackupUnarchivesBackupAndDropsDuplicate() throws {
        let (container, context) = try makeContext()
        _ = container
        let backup = Audiobook(title: "Backup", folderName: "a", isFreeBook: true, catalogId: "lv-123", isDownloaded: false)
        backup.isArchived = true
        let backupID = backup.id
        let duplicate = Audiobook(title: "Duplicate", folderName: "b", isFreeBook: true, catalogId: "lv-123", isDownloaded: false)
        let duplicateID = duplicate.id
        context.insert(backup)
        context.insert(duplicate)
        try context.save()

        try OrphanRestoreService.restoreFreeBackup(replacing: duplicate, with: backup, modelContext: context)

        let remaining = try context.fetch(FetchDescriptor<Audiobook>())
        #expect(remaining.contains { $0.id == backupID })
        #expect(!remaining.contains { $0.id == duplicateID })
        let restored = remaining.first { $0.id == backupID }
        #expect(restored?.isArchived == false)
        #expect(restored?.isDownloaded == false)
    }
}
