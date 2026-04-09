//
//  FreeBookCardView.swift
//  Pageless
//

import SwiftUI

struct FreeBookCardView: View {
    let entry: FreeBookCatalogEntry
    let downloadProgress: Double?
    let isDownloading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                cover

                // "FREE" badge (top trailing)
                VStack {
                    HStack {
                        Spacer()
                        Text("FREE")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                    Spacer()
                }

                // Download icon or progress overlay
                if isDownloading, let progress = downloadProgress {
                    Color.black.opacity(0.4)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 3)
                            .frame(width: 50, height: 50)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 50, height: 50)
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(progress * 100))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Text(entry.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Duration & size info instead of progress bar
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(TimeFormatter.durationSummary(seconds: entry.totalDurationSeconds))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(entry.downloadSizeMB)) MB")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
    }

    private var cover: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.teal.opacity(0.9), .mint.opacity(0.8), .green.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(maxWidth: .infinity, minHeight: 185, maxHeight: 185)
            .overlay {
                if let assetName = entry.coverAssetName, let uiImage = UIImage(named: assetName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
