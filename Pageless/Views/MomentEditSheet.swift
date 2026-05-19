//
//  MomentEditSheet.swift
//  Pageless
//

import SwiftUI

/// A bottom sheet for naming and annotating a moment.
/// Used both when first saving a moment (PlayerView) and when editing an existing one (AudiobookDetailView).
/// All AI-generated metadata fields are fully editable.
struct MomentEditSheet: View {
    let title: String
    let isAiGenerated: Bool

    @Binding var nameInput: String
    @Binding var noteInput: String

    @Binding var categories: [MomentCategory]
    @Binding var quoteLine: String?
    @Binding var characters: [String]
    @Binding var mood: MomentMood?

    let warningMessage: String?
    let onSave: () -> Void
    let onCancel: () -> Void
    let onPlay: (() -> Void)?

    @State private var newCharacterInput: String = ""
    @FocusState private var characterFieldFocused: Bool

    init(
        title: String,
        isAiGenerated: Bool = false,
        nameInput: Binding<String>,
        noteInput: Binding<String>,
        categories: Binding<[MomentCategory]>,
        quoteLine: Binding<String?>,
        characters: Binding<[String]>,
        mood: Binding<MomentMood?>,
        warningMessage: String? = nil,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onPlay: (() -> Void)? = nil
    ) {
        self.title = title
        self.isAiGenerated = isAiGenerated
        self._nameInput = nameInput
        self._noteInput = noteInput
        self._categories = categories
        self._quoteLine = quoteLine
        self._characters = characters
        self._mood = mood
        self.warningMessage = warningMessage
        self.onSave = onSave
        self.onCancel = onCancel
        self.onPlay = onPlay
    }

    var body: some View {
        NavigationStack {
            Form {
                if let warning = warningMessage {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(warning)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                    }
                }

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

                quoteSection
                categoriesSection
                moodSection
                charactersSection

                if let onPlay = onPlay {
                    Section {
                        Button(action: onPlay) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Play from here")
                            }
                            .foregroundStyle(.primary)
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

    // MARK: - Quote

    private var quoteSection: some View {
        Section("Quote") {
            TextField(
                "Apple Intelligence couldn\u{2019}t extract a quote from this sequence",
                text: Binding(
                    get: { quoteLine ?? "" },
                    set: { newValue in
                        quoteLine = newValue.isEmpty ? nil : newValue
                    }
                ),
                axis: .vertical
            )
            .font(.subheadline)
            .italic()
            .lineLimit(2...6)
        }
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        Section("Categories") {
            FlowLayout(spacing: 8) {
                ForEach(categories) { category in
                    TagChip(text: category.displayName) {
                        categories.removeAll { $0 == category }
                    }
                }

                if !availableCategories.isEmpty {
                    Menu {
                        ForEach(availableCategories) { category in
                            Button(category.displayName) {
                                categories.append(category)
                            }
                        }
                    } label: {
                        TagChip.addLabel(text: categories.isEmpty ? "Add category" : "Add")
                    }
                }
            }
        }
    }

    private var availableCategories: [MomentCategory] {
        MomentCategory.allCases.filter { !categories.contains($0) }
    }

    // MARK: - Mood

    private var moodSection: some View {
        Section("Mood") {
            FlowLayout(spacing: 8) {
                if let current = mood {
                    TagChip(text: current.displayName) {
                        mood = nil
                    }
                }

                Menu {
                    if mood != nil {
                        Button("Clear mood", role: .destructive) {
                            mood = nil
                        }
                    }
                    ForEach(MomentMood.allCases) { option in
                        Button {
                            mood = option
                        } label: {
                            if option == mood {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                } label: {
                    TagChip.addLabel(text: mood == nil ? "Add mood" : "Change")
                }
            }
        }
    }

    // MARK: - Characters

    private var charactersSection: some View {
        Section("Characters") {
            if !characters.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(characters, id: \.self) { name in
                        TagChip(text: name) {
                            characters.removeAll { $0 == name }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Add character", text: $newCharacterInput)
                    .submitLabel(.done)
                    .focused($characterFieldFocused)
                    .onSubmit(addCharacter)

                Button(action: addCharacter) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(canAddCharacter ? Color.primary : Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(!canAddCharacter)
            }
        }
    }

    private var canAddCharacter: Bool {
        let trimmed = newCharacterInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !characters.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private func addCharacter() {
        let trimmed = newCharacterInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !characters.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        characters.append(trimmed)
        newCharacterInput = ""
    }
}

// MARK: - Tag chip

private struct TagChip: View {
    let text: String
    let onRemove: (() -> Void)?

    init(text: String, onRemove: (() -> Void)? = nil) {
        self.text = text
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(text)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }

    static func addLabel(text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        )
    }
}

// MARK: - FlowLayout

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
    @Previewable @State var categories: [MomentCategory] = [.action, .tension]
    @Previewable @State var quote: String? = "The dragons descended upon the village like a storm of fire."
    @Previewable @State var characters: [String] = ["Eragon", "Saphira"]
    @Previewable @State var mood: MomentMood? = .dramatic

    MomentEditSheet(
        title: "Edit Moment",
        isAiGenerated: true,
        nameInput: $name,
        noteInput: $note,
        categories: $categories,
        quoteLine: $quote,
        characters: $characters,
        mood: $mood,
        onSave: { },
        onCancel: { },
        onPlay: { }
    )
}
