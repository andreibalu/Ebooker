//
//  ImportAudiobookSheet.swift
//  Pageless
//

import SwiftData
import SwiftUI

struct ImportAudiobookSheet: View {
    let pending: PendingImportSelection
    let onImport: (String, String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var allBooks: [Audiobook]
    @State private var title: String
    @State private var author: String
    @State private var isImporting = false
    @State private var errorMessage = ""
    @State private var isShowingError = false

    init(pending: PendingImportSelection, onImport: @escaping (String, String) throws -> Void) {
        self.pending = pending
        self.onImport = onImport
        _title = State(initialValue: pending.suggestedTitle)
        _author = State(initialValue: pending.suggestedAuthor)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let coverData = pending.coverArtData, let uiImage = UIImage(data: coverData) {
                    Section {
                        HStack {
                            Spacer()
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 200, maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                Section("Details") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)

                    TextField("Author", text: $author)
                        .textInputAutocapitalization(.words)

                    LabeledContent("Files", value: "\(pending.tracks.count)")
                    LabeledContent("Total length", value: TimeFormatter.durationSummary(seconds: pending.totalDuration))
                }

                if showsCloudMatchHint {
                    Section {
                        Label {
                            Text("Already listened to this before? After adding, open the book and tap the **iCloud** button (top right) to match it with your backup and restore your old progress and moments.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "icloud.and.arrow.down")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Imported Files") {
                    ForEach(pending.tracks) { track in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title)
                                    .lineLimit(1)
                                Text(track.originalFileName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(TimeFormatter.clockString(seconds: track.duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Import Audiobook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "Importing..." : "Save") {
                        importAudiobook()
                    }
                    .disabled(isImporting)
                }
            }
            .alert("Could Not Import", isPresented: $isShowingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    /// Shown only when sync is active and at least one cloud-only own book exists to match against —
    /// this is the fallback path when import couldn't auto-match the files to a backup.
    private var showsCloudMatchHint: Bool {
        IcloudSyncGate.isEnabled()
            && allBooks.contains { !$0.isDownloaded && !$0.isFreeBook }
    }

    private func importAudiobook() {
        guard !isImporting else { return }
        isImporting = true

        do {
            try onImport(title, author)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
            isImporting = false
        }
    }
}
