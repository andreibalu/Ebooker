//
//  AudiobookTrackRow.swift
//  Pageless
//

import SwiftUI

struct AudiobookTrackRow: View {
    let audiobook: Audiobook
    let track: AudioTrack
    let openPlayer: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        Button {
            if audiobook.isStreamingOnly {
                openPlayer()
            }
            Task {
                await player.playTrack(at: track.orderIndex, in: audiobook)
                if !audiobook.isStreamingOnly {
                    openPlayer()
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Text("\(track.orderIndex + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .foregroundStyle(.primary)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)

                    Text(TimeFormatter.clockString(seconds: track.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if player.currentAudiobook?.id == audiobook.id, player.currentTrackIndex == track.orderIndex {
                    Image(systemName: "waveform")
                        .foregroundStyle(.primary)
                        .font(.subheadline)
                } else {
                    Image(systemName: "play.circle")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}
