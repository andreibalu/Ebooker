//
//  MatchCloudEntrySheet.swift
//  Pageless
//

import SwiftData
import SwiftUI

/// Lets the user manually match a downloaded local book against an older cloud-only iCloud entry
/// and import everything from it (cloud-wins). Used when auto-match on import didn't find the
/// backup — e.g. the user tapped "Add as new" or imported different files for the same book.
struct MatchCloudEntrySheet: View {
    let localBook: Audiobook
    /// Called after a successful merge so the presenting detail view can pop (the local record is
    /// gone; the surviving cloud entry reappears in the library as downloaded).
    let onMerged: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allBooks: [Audiobook]

    @State private var searchText = ""
    @State private var confirmCandidate: Audiobook?
    @State private var alertMessage: String?

    private var candidates: [Audiobook] {
        allBooks
            .filter { $0.id != localBook.id && !$0.isDownloaded && !$0.isFreeBook }
            .filter {
                searchText.isEmpty
                    || $0.title.localizedCaseInsensitiveContains(searchText)
                    || $0.author.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { ($0.lastPlayedAt ?? $0.createdAt) > ($1.lastPlayedAt ?? $1.createdAt) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "No iCloud backups",
                        systemImage: "icloud",
                        description: Text(searchText.isEmpty
                            ? "There are no cloud-only books to match against."
                            : "No iCloud backups match “\(searchText)”.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(candidates) { book in
                                Button {
                                    confirmCandidate = book
                                } label: {
                                    candidateRow(book)
                                }
                                .buttonStyle(.plain)
                            }
                        } footer: {
                            Text("Importing replaces this book’s current progress, moments, and EQ with the iCloud backup’s.")
                        }
                    }
                }
            }
            .navigationTitle("Match with iCloud")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search backups")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Import from iCloud backup?",
                isPresented: Binding(
                    get: { confirmCandidate != nil },
                    set: { if !$0 { confirmCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Import Everything", role: .destructive) {
                    if let candidate = confirmCandidate { performMerge(into: candidate) }
                }
                Button("Cancel", role: .cancel) { confirmCandidate = nil }
            } message: {
                Text("Your current progress and moments for ‘\(localBook.title)’ will be replaced by the iCloud backup.")
            }
            .alert("Couldn’t Match", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func performMerge(into candidate: Audiobook) {
        confirmCandidate = nil
        do {
            _ = try OrphanRestoreService.merge(localBook: localBook, into: candidate, modelContext: modelContext)
            dismiss()
            onMerged()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func candidateRow(_ book: Audiobook) -> some View {
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
            Image(systemName: "icloud.and.arrow.down")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func metaLine(for book: Audiobook) -> some View {
        let count = book.moments.count
        let pieces: [String] = [
            count > 0 ? "\(count) moment\(count == 1 ? "" : "s")" : nil,
            book.progress > 0 ? "\(Int(book.progress * 100))%" : nil,
        ].compactMap { $0 }
        return Text(pieces.isEmpty ? "No saved progress" : pieces.joined(separator: " · "))
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
}
