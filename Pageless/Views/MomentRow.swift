//
//  MomentRow.swift
//  Pageless
//

import SwiftUI
import UIKit

struct MomentRow: View {
    let audiobook: Audiobook
    let moment: Moment
    let openPlayer: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager
    @State private var isEditing = false
    @State private var editNameInput = ""
    @State private var editNoteInput = ""
    @State private var editCategories: [MomentCategory] = []
    @State private var editQuoteLine: String? = nil
    @State private var editCharacters: [String] = []
    @State private var editMood: MomentMood? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingSwipe = false
    @State private var swipeBaseOffset: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    /// Width of the exposed delete action (Mail-style).
    private let revealWidth: CGFloat = 82
    private let springOpen = Animation.spring(response: 0.38, dampingFraction: 0.86)
    private let springClose = Animation.spring(response: 0.4, dampingFraction: 0.88)

    private var effectiveWidth: CGFloat {
        max(containerWidth, 320)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteActionBackground

            rowForeground
                .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .leading) {
                    if moment.isPinned {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.45))
                            .frame(width: 3)
                    }
                }
                .offset(x: dragOffset)
                .gesture(swipeGesture)
                .onTapGesture {
                    if isRevealed {
                        withAnimation(springClose) {
                            dragOffset = 0
                        }
                    } else {
                        editNameInput = moment.label
                        editNoteInput = moment.notes ?? ""
                        editCategories = moment.categories
                        editQuoteLine = moment.quoteLine
                        editCharacters = moment.characters
                        editMood = moment.mood
                        isEditing = true
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateWidth(geo.size.width) }
                    .onChange(of: geo.size.width) { _, w in updateWidth(w) }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $isEditing) {
            MomentEditSheet(
                title: "Edit Moment",
                isAiGenerated: moment.aiGeneratedName,
                nameInput: $editNameInput,
                noteInput: $editNoteInput,
                categories: $editCategories,
                quoteLine: $editQuoteLine,
                characters: $editCharacters,
                mood: $editMood,
                onSave: {
                    let trimmedName = editNameInput.trimmingCharacters(in: .whitespaces)
                    if !trimmedName.isEmpty {
                        moment.label = trimmedName
                    }
                    let trimmedNote = editNoteInput.trimmingCharacters(in: .whitespaces)
                    moment.notes = trimmedNote.isEmpty ? nil : trimmedNote
                    moment.categories = editCategories
                    let trimmedQuote = editQuoteLine?.trimmingCharacters(in: .whitespacesAndNewlines)
                    moment.quoteLine = (trimmedQuote?.isEmpty ?? true) ? nil : trimmedQuote
                    moment.characters = editCharacters
                    moment.mood = editMood
                    isEditing = false
                },
                onCancel: { isEditing = false },
                onPlay: {
                    Task {
                        await player.playTrack(at: moment.trackIndex, in: audiobook, time: moment.time)
                        isEditing = false
                        openPlayer()
                    }
                }
            )
        }
    }

    private var isRevealed: Bool {
        dragOffset <= -revealWidth * 0.5
    }

    private var deleteActionBackground: some View {
        Button {
            commitDeleteAnimated()
        } label: {
            Text("Delete")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.red.opacity(0.92))
        )
        .accessibilityLabel("Delete moment")
    }

    private var rowForeground: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                moment.isPinned.toggle()
            } label: {
                Image(systemName: moment.isPinned ? "pin.fill" : "flag.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(moment.isPinned ? Color.primary : Color.secondary)
                    .frame(width: 24, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(moment.isPinned ? "Unpin moment" : "Pin moment")
            .accessibilityHint(
                moment.isPinned
                    ? "Removes this moment from the top of the list"
                    : "Keeps this moment at the top of the list"
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(moment.label)
                    .foregroundStyle(.primary)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)

                Text(TimeFormatter.clockString(seconds: moment.time))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let note = moment.notes, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }

            Spacer()

            Image(systemName: "play.circle")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func updateWidth(_ w: CGFloat) {
        guard w > 1 else { return }
        if abs(containerWidth - w) > 0.5 {
            containerWidth = w
        }
    }

    private func commitDeleteAnimated() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let w = effectiveWidth
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            dragOffset = -w - 24
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            onDelete()
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height

                if !isDraggingSwipe {
                    let horizontalIntent = abs(dx) + 8 >= abs(dy) || dx < -12
                    guard horizontalIntent || dragOffset < 0 else { return }
                    isDraggingSwipe = true
                    swipeBaseOffset = dragOffset
                }

                let w = effectiveWidth
                let next = swipeBaseOffset + dx
                // Allow a little rubber-band past full width; cap right at 0.
                let minX = -w * 1.02
                dragOffset = min(0, max(next, minX))
            }
            .onEnded { value in
                isDraggingSwipe = false
                let w = effectiveWidth
                let current = swipeBaseOffset + value.translation.width
                let predicted = swipeBaseOffset + value.predictedEndTranslation.width

                // Full swipe should require a deliberate commit, not a tiny flick.
                let deleteDistance = max(w * 0.72, revealWidth + 120)
                let shouldFullDelete =
                    current <= -deleteDistance
                    || (current <= -w * 0.58 && predicted <= -w * 0.9)

                if shouldFullDelete {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                        dragOffset = -w - 24
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                        onDelete()
                    }
                    return
                }

                // Partial swipe → snap open to show Delete, or close.
                if current <= -revealWidth * 0.55 || predicted <= -revealWidth * 0.85 {
                    withAnimation(springOpen) {
                        dragOffset = -revealWidth
                    }
                } else {
                    withAnimation(springClose) {
                        dragOffset = 0
                    }
                }
            }
    }
}
