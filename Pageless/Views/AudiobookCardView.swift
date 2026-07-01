//
//  AudiobookCardView.swift
//  Pageless
//

import SwiftUI

struct AudiobookCardView: View {
    let audiobook: Audiobook
    let isCurrentlyPlaying: Bool
    let isLoadingPlayback: Bool
    let downloadEntry: LibriVoxDownloadManager.Entry?

    @State private var folderSizeMB: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                cover

                // Status badge (top trailing of cover)
                if isLoadingPlayback {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.primary)
                        Text("Connecting")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
                } else if isCurrentlyPlaying {
                    Label("Playing", systemImage: "waveform")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                } else if let last = audiobook.lastPlayedAt {
                    Text(TimeFormatter.relativeDateString(for: last))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }

                // iCloud backup assurance (top leading of cover) — self-hides unless sync is active.
                VStack {
                    HStack {
                        ICloudBackupBadge(style: .overlayIcon)
                            .padding(10)
                        Spacer()
                    }
                    Spacer()
                }

                // Favorite heart button (bottom trailing of cover)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                audiobook.isFavorite.toggle()
                            }
                        } label: {
                            Image(systemName: audiobook.isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(audiobook.isFavorite ? Color.red : Color.white)
                                .padding(9)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(audiobook.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Text(audiobook.displayAuthor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(TimeFormatter.durationSummary(seconds: audiobook.totalDuration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let status = LibriVoxDownloadPresentation.cardStatus(
                        entry: downloadEntry,
                        isStreamingOnly: audiobook.isStreamingOnly
                    ) {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: downloadEntry == nil
                                  ? "antenna.radiowaves.left.and.right"
                                  : "arrow.down.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    } else if let mb = folderSizeMB {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(mb) MB")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Custom slim progress capsule
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: geo.size.width * audiobook.progress, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(14)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
        .onAppear {
            folderSizeMB = LibraryImportService.folderSizeMB(for: audiobook)
        }
    }

    private var cover: some View {
        // Use a fixed-size container as the layout anchor, then overlay the image.
        // This prevents scaledToFill from inflating the card height via its ideal size.
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 185, maxHeight: 185)
            .overlay {
                if let coverArtData = audiobook.coverArtData,
                   let image = UIImage(data: coverArtData)
                {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    GeneratedCoverView(title: audiobook.title)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

}
