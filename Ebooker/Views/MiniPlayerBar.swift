//
//  MiniPlayerBar.swift
//  Ebooker
//

import SwiftUI

struct MiniPlayerBar: View {
    let openPlayer: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        VStack(spacing: 0) {
            // Book-level progress strip
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.primary.opacity(0.4))
                        .frame(width: geo.size.width * (player.bookProgress), height: 3)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            HStack(spacing: 12) {
                miniCover

                VStack(alignment: .leading, spacing: 3) {
                    Text(player.currentAudiobook?.title ?? "Nothing playing")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(player.currentTrack?.title ?? "Choose an audiobook")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.primary, in: Circle())
                        .foregroundStyle(Color.cardWhite)
                }
                .buttonStyle(.plain)

                Button {
                    player.nextTrack()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!player.canGoToNextTrack)
                .opacity(player.canGoToNextTrack ? 1 : 0.35)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(
            Color.cardWhite
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 18, y: -2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: openPlayer)
    }

    private var miniCover: some View {
        Group {
            if
                let coverArtData = player.currentAudiobook?.coverArtData,
                let image = UIImage(data: coverArtData)
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(.white.opacity(0.9))
                    }
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
