//
//  MiniPlayerBar.swift
//  Pageless
//

import SwiftUI

struct MiniPlayerBar: View {
    let openPlayer: () -> Void
    var onDragChanged: ((CGFloat) -> Void)? = nil
    var onDragEnded: ((CGFloat, CGFloat) -> Void)? = nil

    @EnvironmentObject private var player: AudioPlayerManager

    // Secondary chapter line. Single-track books already show the (renamable) book title
    // on the line above, so the lone "Chapter 1" file-metadata title is dropped to avoid
    // a duplicate; only distinct multi-track chapter names render here.
    private var miniSecondaryLine: String? {
        guard let track = player.currentTrack else { return nil }
        guard (player.currentAudiobook?.tracks.count ?? 0) > 1 else { return nil }
        let bookTitle = player.currentAudiobook?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trackTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trackTitle.isEmpty || trackTitle == bookTitle { return nil }
        return trackTitle
    }

    var body: some View {
        VStack(spacing: 0) {
            // Full-width progress strip flush at the very top
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 2)
                    Rectangle()
                        .fill(Color.primary.opacity(0.45))
                        .frame(width: geo.size.width * player.bookProgress, height: 2)
                }
            }
            .frame(height: 2)

            HStack(alignment: .center, spacing: 12) {
                miniCover

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentAudiobook?.title ?? "Nothing playing")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if let secondary = miniSecondaryLine {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if player.isPreparingPlayback {
                        Text("Connecting to stream…")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.amber)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                AirPlayRoutePickerView()
                    .frame(width: 32, height: 32)
                    .padding(.trailing, 2)

                Button {
                    if player.isPreparingPlayback {
                        player.pause()
                    } else {
                        player.togglePlayback()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 42, height: 42)
                        if player.isPreparingPlayback {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.cardWhite)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.cardWhite)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 0)
        }
        // Sharp rectangle (YouTube Music–style); extends into home-indicator area
        .background(
            Color.cardWhite
                .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: openPlayer)
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let up = max(0, -value.translation.height)
                    onDragChanged?(up)
                }
                .onEnded { value in
                    let up = max(0, -value.translation.height)
                    let velocityUp = max(0, -value.velocity.height)
                    onDragEnded?(up, velocityUp)
                }
        )
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
                GeneratedCoverView(title: player.currentAudiobook?.title ?? "Unpaged")
            }
        }
        .frame(width: 48, height: 48)
        .clipped()
    }
}
