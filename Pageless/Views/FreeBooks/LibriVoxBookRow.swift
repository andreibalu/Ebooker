//
//  LibriVoxBookRow.swift
//  Pageless
//

import SwiftUI

struct LibriVoxBookRow: View {
    let book: LibriVoxBook
    var browseViewModel: BrowseLibriVoxViewModel?

    var body: some View {
        HStack(spacing: 12) {
            coverThumbnail
            info
            Spacer(minLength: 0)
            if let browseViewModel {
                sampleButton(browseViewModel: browseViewModel)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private func sampleButton(browseViewModel: BrowseLibriVoxViewModel) -> some View {
        Button {
            if SamplePlayer.shared.isActive(for: book.id) {
                SamplePlayer.shared.stop()
            } else {
                Task {
                    if let url = await browseViewModel.fetchFirstTrackURL(for: book) {
                        SamplePlayer.shared.playSample(bookId: book.id, trackURL: url)
                    }
                }
            }
        } label: {
            Group {
                if case .loading(let id) = SamplePlayer.shared.state, id == book.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: SamplePlayer.shared.isActive(for: book.id) ? "stop.circle.fill" : "play.circle")
                        .font(.title3)
                        .foregroundStyle(SamplePlayer.shared.isActive(for: book.id) ? .red : .primary)
                }
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }

    private var coverThumbnail: some View {
        AsyncImage(url: book.bestCoverURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            default:
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                    Image(systemName: "book.closed")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(book.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text(book.authorDisplay)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(book.formattedDuration)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
