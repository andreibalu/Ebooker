//
//  FreeBookDetailSheet.swift
//  Pageless
//

import SwiftUI

struct FreeBookDetailSheet: View {
    let entry: FreeBookCatalogEntry
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double?
    let downloadError: String?
    let onDownload: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    coverSection
                    metadataSection
                    descriptionSection
                    trackListSection
                    downloadSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color.cream.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Cover

    private var coverSection: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.teal.opacity(0.9), .mint.opacity(0.8), .green.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220)
            .overlay {
                if let assetName = entry.coverAssetName, let uiImage = UIImage(named: assetName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(spacing: 12) {
            Text(entry.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(entry.author)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                metadataItem(icon: "clock", label: TimeFormatter.durationSummary(seconds: entry.totalDurationSeconds))
                metadataItem(icon: "arrow.down.doc", label: "\(Int(entry.downloadSizeMB)) MB")
                metadataItem(icon: "list.number", label: "\(entry.tracks.count) chapters")
            }
            .padding(.top, 4)
        }
    }

    private func metadataItem(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)
            Text(BookDescriptionFormatting.plainText(fromHTMLFragment: entry.description))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Track List

    private var trackListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chapters")
                .font(.headline)

            ForEach(entry.tracks) { track in
                HStack {
                    Text(track.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Text(TimeFormatter.durationSummary(seconds: track.durationSeconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Download Action

    private var downloadSection: some View {
        VStack(spacing: 12) {
            if isDownloaded {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.green.opacity(0.1), in: Capsule())
            } else if isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: downloadProgress ?? 0)
                        .progressViewStyle(.linear)
                        .tint(.primary)

                    Text("Downloading... \(Int((downloadProgress ?? 0) * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
                .padding(.vertical, 8)
            } else {
                Button {
                    onDownload()
                } label: {
                    Label("Download (\(Int(entry.downloadSizeMB)) MB)", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())
            }

            if let error = downloadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
