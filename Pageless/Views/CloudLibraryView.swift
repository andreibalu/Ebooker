//
//  CloudLibraryView.swift
//  Pageless
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The user-facing iCloud Library: every book the user has ever added lives here permanently —
/// shown whether or not its audio is present on this device — so the user can always confirm their
/// data is backed up. Four buckets cover every possible state with nothing hidden:
///   • "On this iPhone"     — downloaded own + free books (audio present locally).
///   • "Streaming"          — active free books kept as streaming entries (backed up, no local files).
///   • "In iCloud only"     — own books synced without their audio; restore via a "Locate…" picker.
///   • "Removed free books" — free books the user removed; one-tap "Stream" brings them back.
/// A row is only ever removed from iCloud by an explicit swipe-to-delete here.
struct CloudLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allBooks: [Audiobook]

    @AppStorage(IcloudSyncGate.preferenceKey) private var iCloudSyncEnabled = false

    @State private var pickingForBook: Audiobook?
    @State private var fileImporterPresented = false
    @State private var alertMessage: String?
    @State private var streamRestoreInFlight: Set<UUID> = []
    @State private var navigateToBook: Audiobook?
    @State private var deleteCandidate: Audiobook?

    private func byRecency(_ books: [Audiobook]) -> [Audiobook] {
        books.sorted { ($0.lastPlayedAt ?? $0.createdAt) > ($1.lastPlayedAt ?? $1.createdAt) }
    }

    // Everything whose audio is present on this device — own imports and downloaded free books alike.
    private var onThisPhone: [Audiobook] {
        byRecency(allBooks.filter { $0.isDownloaded && !$0.isArchived })
    }

    // Active free books kept in the library as streaming entries (no local files, but fully backed up).
    // Surfacing these is the whole point of "I always see every book": a streaming free book is safe
    // in iCloud even though nothing is downloaded.
    private var streamingFree: [Audiobook] {
        byRecency(allBooks.filter { !$0.isDownloaded && $0.isFreeBook && !$0.isArchived })
    }

    // Own books that synced down without their audio on this device — restorable via "Locate…".
    private var ownOrphans: [Audiobook] {
        byRecency(allBooks.filter { !$0.isDownloaded && !$0.isFreeBook })
    }

    // Free books the user removed from their library but that stay backed up in iCloud ("Stream" to
    // bring them back).
    private var archivedFree: [Audiobook] {
        byRecency(allBooks.filter { $0.isArchived && $0.isFreeBook })
    }

    var body: some View {
        List {
            if !iCloudSyncEnabled {
                Section {
                    Text("Turn on iCloud sync in Settings to back up your library and see it across devices.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
            }

            if !onThisPhone.isEmpty {
                Section("On this iPhone") {
                    ForEach(onThisPhone) { book in
                        downloadedRow(book)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    deleteCandidate = book
                                }
                            }
                    }
                }
            }

            if !streamingFree.isEmpty {
                Section("Streaming") {
                    ForEach(streamingFree) { book in
                        streamingFreeRow(book)
                    }
                }
            }

            if !ownOrphans.isEmpty {
                Section("In iCloud only") {
                    ForEach(ownOrphans) { book in
                        ownBookRow(book)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    deleteCandidate = book
                                }
                            }
                    }
                }
            }

            if !archivedFree.isEmpty {
                Section("Removed free books") {
                    ForEach(archivedFree) { book in
                        freeBookRow(book)
                    }
                }
            }

            if onThisPhone.isEmpty && streamingFree.isEmpty && ownOrphans.isEmpty && archivedFree.isEmpty && iCloudSyncEnabled {
                Section {
                    Text("Your iCloud Library is empty. Books you import will be backed up here automatically.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("iCloud Library")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $navigateToBook) { book in
            AudiobookDetailView(audiobook: book) {}
        }
        .fileImporter(
            isPresented: $fileImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result)
        }
        .confirmationDialog(
            "Remove from iCloud?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let book = deleteCandidate { permanentlyDelete(book) }
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("Permanently removes ‘\(deleteCandidate?.title ?? "this book")’ and its progress, moments, and EQ from iCloud and all your devices. This can’t be undone.")
        }
        .alert("iCloud Library", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    @ViewBuilder
    private func downloadedRow(_ book: Audiobook) -> some View {
        HStack(spacing: 12) {
            cover(for: book)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(book.displayAuthor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                metaLine(for: book)
            }
            Spacer()
            Label("Saved", systemImage: "checkmark.icloud")
                .labelStyle(.iconOnly)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func streamingFreeRow(_ book: Audiobook) -> some View {
        HStack(spacing: 12) {
            cover(for: book)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(book.displayAuthor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                metaLine(for: book)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Label("Streaming", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Label("Backed up", systemImage: "checkmark.icloud")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func ownBookRow(_ book: Audiobook) -> some View {
        HStack(spacing: 12) {
            cover(for: book)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(book.displayAuthor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                metaLine(for: book)
            }
            Spacer()
            Button("Locate…") {
                pickingForBook = book
                fileImporterPresented = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func freeBookRow(_ book: Audiobook) -> some View {
        HStack(spacing: 12) {
            cover(for: book)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(book.displayAuthor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                metaLine(for: book)
            }
            Spacer()
            if hasStreamingURLs(book) {
                Button("Stream") {
                    restoreStreaming(book: book)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(streamRestoreInFlight.contains(book.id))
            } else {
                Text("Open in Free Books tab")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func metaLine(for book: Audiobook) -> some View {
        let count = book.moments.count
        let pieces: [String] = [
            count > 0 ? "\(count) moment\(count == 1 ? "" : "s")" : nil,
            book.progress > 0 ? "\(Int(book.progress * 100))%" : nil,
        ].compactMap { $0 }
        return Text(pieces.joined(separator: " · "))
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func cover(for book: Audiobook) -> some View {
        Group {
            if let data = book.coverArtData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                GeneratedCoverView(title: book.title)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func hasStreamingURLs(_ book: Audiobook) -> Bool {
        book.tracks.contains { $0.remoteURL != nil }
    }

    private func permanentlyDelete(_ book: Audiobook) {
        deleteCandidate = nil
        do {
            try LibraryImportService.deleteAudiobook(book, deleteFiles: true, modelContext: modelContext)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func restoreStreaming(book: Audiobook) {
        // Archived free books keep their remote track URLs — clearing the archive flag returns the
        // book to the library as a streaming entry the user can play again (or re-download).
        streamRestoreInFlight.insert(book.id)
        defer { streamRestoreInFlight.remove(book.id) }
        book.isArchived = false
        book.isDownloaded = false
        try? modelContext.save()
        alertMessage = "‘\(book.title)’ is back in your library — open it to stream."
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        guard let book = pickingForBook else { return }
        switch result {
        case .success(let urls):
            let audioURLs = urls
                .filter { !$0.hasDirectoryPath }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            guard !audioURLs.isEmpty else { return }
            let accessed = audioURLs.filter { $0.startAccessingSecurityScopedResource() }
            Task {
                defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
                do {
                    let pending = try await LibraryImportService.prepareImport(from: audioURLs)
                    let pendingFingerprints = Set(pending.tracks.compactMap { $0.contentFingerprint })
                    let orphanFingerprints = Set(book.tracks.compactMap { $0.contentFingerprint })
                    let matched = !pendingFingerprints.isEmpty && !pendingFingerprints.isDisjoint(with: orphanFingerprints)
                    if !matched {
                        alertMessage = "These files don't match the iCloud copy of ‘\(book.title)’. Tap again to adopt anyway, or pick a different file."
                        // Best-effort: still adopt — the user explicitly chose this row, the
                        // mismatch warning above is informational and gates a second tap visually.
                    }
                    _ = try OrphanRestoreService.adopt(orphan: book, pending: pending, modelContext: modelContext)
                    pickingForBook = nil
                    navigateToBook = book
                } catch {
                    alertMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            alertMessage = error.localizedDescription
        }
    }
}
