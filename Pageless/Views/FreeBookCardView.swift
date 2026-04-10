//
//  FreeBookCardView.swift
//  Pageless
//

import SwiftUI

struct FreeBookCardView: View {
    let entry: FreeBookCatalogEntry
    let downloadProgress: Double?
    let isDownloading: Bool
    let onDownload: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            cover

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Text(entry.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(TimeFormatter.durationSummary(seconds: entry.totalDurationSeconds))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("\(Int(entry.downloadSizeMB)) MB")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            downloadControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.teal.opacity(0.9), .mint.opacity(0.8), .green.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)

            if let assetName = entry.coverAssetName, let uiImage = UIImage(named: assetName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.95))
            }
        }
    }

    @ViewBuilder
    private var downloadControl: some View {
        if isDownloading, let progress = downloadProgress {
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 2.5)
                        .frame(width: 34, height: 34)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(progress * 100))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
        } else {
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
