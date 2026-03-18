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

    let categories: [MomentCategory]
    let quoteLine: String?
    let characters: [String]
    let mood: MomentMood?

    let onSave: () -> Void
    let onCancel: () -> Void
    let onPlay: (() -> Void)?

    init(
        title: String,
        isAiGenerated: Bool = false,
        nameInput: Binding<String>,
        noteInput: Binding<String>,
        categories: [MomentCategory] = [],
        quoteLine: String? = nil,
        characters: [String] = [],
        mood: MomentMood? = nil,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onPlay: (() -> Void)? = nil
    ) {
        self.title = title
        self.isAiGenerated = isAiGenerated
        self._nameInput = nameInput
        self._noteInput = noteInput
        self.categories = categories
        self.quoteLine = quoteLine
        self.characters = characters
        self.mood = mood
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

                if let quote = quoteLine, !quote.isEmpty {
                    Section("Quote") {
                        Text("\u{201C}\(quote)\u{201D}")
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }

                if !categories.isEmpty {
                    Section("Categories") {
                        FlowLayout(spacing: 8) {
                            ForEach(categories) { category in
                                Text(category.displayName)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.08), in: Capsule())
                            }
                        }
                    }
                }

                if let mood = mood {
                    Section("Mood") {
                        Text(mood.displayName)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }

                if !characters.isEmpty {
                    Section("Characters") {
                        Text(characters.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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

/// Simple flow layout for horizontal wrapping of tags.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
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
        categories: [.action, .tension],
        quoteLine: "The dragons descended upon the village like a storm of fire.",
        characters: ["Eragon", "Saphira"],
        mood: .dramatic,
        onSave: { },
        onCancel: { },
        onPlay: { }
    )
}
