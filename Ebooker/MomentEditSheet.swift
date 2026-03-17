//
//  MomentEditSheet.swift
//  Ebooker
//

import SwiftUI

/// A bottom sheet for naming and optionally annotating a moment.
/// Used both when first saving a moment (PlayerView) and when editing an existing one (AudiobookDetailView).
struct MomentEditSheet: View {
    let title: String
    let isAiGenerated: Bool

    @Binding var nameInput: String
    @Binding var noteInput: String

    let onSave: () -> Void
    let onCancel: () -> Void
    let onPlay: (() -> Void)?

    init(
        title: String,
        isAiGenerated: Bool = false,
        nameInput: Binding<String>,
        noteInput: Binding<String>,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onPlay: (() -> Void)? = nil
    ) {
        self.title = title
        self.isAiGenerated = isAiGenerated
        self._nameInput = nameInput
        self._noteInput = noteInput
        self.onSave = onSave
        self.onCancel = onCancel
        self.onPlay = onPlay
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Moment name", text: $nameInput)
                }
                Section {
                    TextField(
                        "Add a note (optional)",
                        text: $noteInput,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                } header: {
                    HStack {
                        Text("Note")
                        if isAiGenerated {
                            Spacer()
                            Label("AI generated", systemImage: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let onPlay = onPlay {
                    Section {
                        Button(action: {
                            onPlay()
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Play from here")
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onSave)
                        .disabled(nameInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    @Previewable @State var name = "Dragons Attack"
    @Previewable @State var note = "The village comes under attack by dragons. Key turning point in the story."

    MomentEditSheet(
        title: "Edit Moment",
        isAiGenerated: true,
        nameInput: $name,
        noteInput: $note,
        onSave: { },
        onCancel: { },
        onPlay: { }
    )
}
