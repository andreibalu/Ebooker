//
//  MomentRow.swift
//  Ebooker
//

import SwiftUI

struct MomentRow: View {
    let audiobook: Audiobook
    let moment: Moment
    let openPlayer: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager
    @State private var isEditing = false
    @State private var editNameInput = ""
    @State private var editNoteInput = ""

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "flag.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)

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
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .onTapGesture {
            editNameInput = moment.label
            editNoteInput = moment.notes ?? ""
            isEditing = true
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
                categories: moment.categories,
                quoteLine: moment.quoteLine,
                characters: moment.characters,
                mood: moment.mood,
                onSave: {
                    let trimmedName = editNameInput.trimmingCharacters(in: .whitespaces)
                    if !trimmedName.isEmpty {
                        moment.label = trimmedName
                    }
                    let trimmedNote = editNoteInput.trimmingCharacters(in: .whitespaces)
                    moment.notes = trimmedNote.isEmpty ? nil : trimmedNote
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
}
