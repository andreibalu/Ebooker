//
//  LibraryViewModel.swift
//  Pageless
//

import Foundation
import SwiftData

struct RestoreMatchCandidate: Identifiable {
    let id = UUID()
    let pending: PendingImportSelection
    let orphan: Audiobook
}

@MainActor
@Observable
final class LibraryViewModel {
    // MARK: - Import workflow

    var pendingImport: PendingImportSelection?
    var urlsHoldingSecurityAccess: [URL] = []

    /// Set when `prepareImport` detects an orphan cloud-synced book whose tracks fingerprint-match
    /// the file the user just picked. The ImportAudiobookSheet branches on this and offers
    /// "Restore" vs "Add as new" before committing.
    var restoreMatch: RestoreMatchCandidate?

    // MARK: - Delete / rename

    var deleteCandidate: Audiobook?
    var renameCandidate: Audiobook?
    var renameTitleInput: String = ""

    // MARK: - Alert state

    var alertMessage = ""
    var isShowingAlert = false

    // MARK: - Import

    func handleImportSelection(_ result: Result<[URL], Error>, modelContext: ModelContext) {
        switch result {
        case .success(let urls):
            let audioURLs = urls
                .filter { !$0.hasDirectoryPath }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            guard !audioURLs.isEmpty else {
                presentAlert(message: "Choose at least one audio file.")
                return
            }
            let accessed: [URL] = audioURLs.filter { $0.startAccessingSecurityScopedResource() }
            urlsHoldingSecurityAccess = accessed
            Task {
                do {
                    let pending = try await LibraryImportService.prepareImport(from: audioURLs)
                    if let orphan = OrphanRestoreService.findMatch(for: pending, modelContext: modelContext) {
                        restoreMatch = RestoreMatchCandidate(pending: pending, orphan: orphan)
                    } else {
                        pendingImport = pending
                    }
                } catch {
                    releaseSecurityScopedAccess()
                    presentAlert(message: error.localizedDescription)
                }
            }
        case .failure(let error):
            presentAlert(message: error.localizedDescription)
        }
    }

    func importAudiobook(_ pending: PendingImportSelection, title: String, author: String, modelContext: ModelContext) throws {
        _ = try LibraryImportService.importAudiobook(
            from: pending,
            title: title,
            author: author,
            modelContext: modelContext
        )
        pendingImport = nil
        releaseSecurityScopedAccess()
    }

    /// User accepted the auto-match: write files into the orphan's folder and adopt its metadata.
    func adoptRestoreMatch(modelContext: ModelContext) {
        guard let candidate = restoreMatch else { return }
        do {
            _ = try OrphanRestoreService.adopt(
                orphan: candidate.orphan,
                pending: candidate.pending,
                modelContext: modelContext
            )
            restoreMatch = nil
            releaseSecurityScopedAccess()
        } catch {
            presentAlert(message: error.localizedDescription)
        }
    }

    /// User rejected the match: fall through to the normal new-book import sheet.
    func dismissRestoreMatchAndAddAsNew() {
        guard let candidate = restoreMatch else { return }
        pendingImport = candidate.pending
        restoreMatch = nil
    }

    /// User cancelled both flows; release security scopes.
    func cancelRestoreMatch() {
        restoreMatch = nil
        releaseSecurityScopedAccess()
    }

    func releaseSecurityScopedAccess() {
        for url in urlsHoldingSecurityAccess {
            url.stopAccessingSecurityScopedResource()
        }
        urlsHoldingSecurityAccess = []
    }

    // MARK: - Delete

    func deleteAudiobook(alsoDeleteFiles: Bool, modelContext: ModelContext) {
        guard let deleteCandidate else { return }
        do {
            try LibraryImportService.deleteAudiobook(
                deleteCandidate,
                deleteFiles: alsoDeleteFiles,
                modelContext: modelContext
            )
            self.deleteCandidate = nil
        } catch {
            presentAlert(message: error.localizedDescription)
        }
    }

    /// Sync-on path: removes the audio from this iPhone but keeps the synced record in the
    /// iCloud Library so it can be restored later. Mirrors `deleteAudiobook` but never deletes
    /// the record.
    func softDeleteAudiobook(modelContext: ModelContext) {
        guard let deleteCandidate else { return }
        do {
            try LibraryImportService.softDeleteAudiobook(deleteCandidate, modelContext: modelContext)
            self.deleteCandidate = nil
        } catch {
            presentAlert(message: error.localizedDescription)
        }
    }

    func deleteFreeBook(_ audiobook: Audiobook, modelContext: ModelContext) {
        do {
            if IcloudSyncGate.isEnabled() {
                // Sync on: keep the synced record in the iCloud Library (same permanence guarantee
                // as own books) so the user can re-stream it later. Drop local files + archive.
                try LibraryImportService.archiveFreeBook(audiobook, modelContext: modelContext)
            } else {
                // Sync off: no cloud copy to preserve, so hard-delete as before.
                try LibraryImportService.deleteAudiobook(
                    audiobook,
                    deleteFiles: audiobook.isDownloaded,
                    modelContext: modelContext
                )
            }
        } catch {
            presentAlert(message: error.localizedDescription)
        }
    }

    // MARK: - Rename

    func beginRename(_ audiobook: Audiobook) {
        renameTitleInput = audiobook.title
        renameCandidate = audiobook
    }

    func commitRename() {
        let trimmed = renameTitleInput.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            renameCandidate?.title = trimmed
        }
        renameCandidate = nil
    }

    // MARK: - Sorting

    func sorted(_ books: [Audiobook], by rawValue: String) -> [Audiobook] {
        switch LibrarySortOption(rawValue: rawValue) ?? .recent {
        case .recent:
            books.sorted {
                let lhs = $0.lastPlayedAt ?? $0.createdAt
                let rhs = $1.lastPlayedAt ?? $1.createdAt
                return lhs > rhs
            }
        case .title:
            books.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .author:
            books.sorted {
                let left = $0.author.isEmpty ? $0.title : $0.author
                let right = $1.author.isEmpty ? $1.title : $1.author
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
        case .duration:
            books.sorted { $0.totalDuration > $1.totalDuration }
        case .dateAdded:
            books.sorted { $0.createdAt > $1.createdAt }
        }
    }

    // MARK: - Helpers

    func presentAlert(message: String) {
        alertMessage = message
        isShowingAlert = true
    }
}
