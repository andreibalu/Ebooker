//
//  LibraryViewModel.swift
//  Pageless
//

import Foundation
import SwiftData

@MainActor
@Observable
final class LibraryViewModel {
    // MARK: - Import workflow

    var pendingImport: PendingImportSelection?
    var urlsHoldingSecurityAccess: [URL] = []

    // MARK: - Delete / rename

    var deleteCandidate: Audiobook?
    var renameCandidate: Audiobook?
    var renameTitleInput: String = ""

    // MARK: - Alert state

    var alertMessage = ""
    var isShowingAlert = false

    // MARK: - Import

    func handleImportSelection(_ result: Result<[URL], Error>) {
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
                    pendingImport = try await LibraryImportService.prepareImport(from: audioURLs)
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
        let audiobook = try LibraryImportService.importAudiobook(
            from: pending,
            title: title,
            author: author,
            modelContext: modelContext
        )
        SpotlightService.index(audiobook)
        pendingImport = nil
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
        SpotlightService.deindex(deleteCandidate)
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
