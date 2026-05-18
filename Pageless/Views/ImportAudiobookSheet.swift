//
//  ImportAudiobookSheet.swift
//  Pageless
//

import SwiftUI

struct ImportAudiobookSheet: View {
    let pending: PendingImportSelection
    let onImport: (String, String) throws -> Void

    @Environment(\.dismiss) private var dismiss
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
