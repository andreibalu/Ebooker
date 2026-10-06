//
//  ChapterListSheet.swift
//  Pageless
//

import SwiftUI

/// The player's chapter list: every chapter of the current book (embedded chapters of a
/// single-file book, or one row per file), with the playing chapter highlighted.
struct ChapterListSheet: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(player.chapters) { chapter in
                    row(for: chapter)
                        .id(chapter.id)
                }
                .listStyle(.plain)
                .onAppear {
                    if let index = player.currentChapterIndex {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(for chapter: PlaybackChapter) -> some View {
        let isCurrent = player.currentChapterIndex == chapter.index
        return Button {
            player.playChapter(chapter)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Text("\(chapter.index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24)

                Text(chapter.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.subheadline)
                        .foregroundStyle(Color.amber)
                        .accessibilityHidden(true)
                }

                Text(TimeFormatter.clockString(seconds: chapter.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isCurrent ? Color.amber.opacity(0.12) : Color.clear)
        .accessibilityLabel("Chapter \(chapter.index + 1), \(chapter.title)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("chapters.row.\(chapter.index)")
    }
}
