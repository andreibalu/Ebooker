//
//  LibriVoxBookRow.swift
//  Pageless
//

import SwiftUI

/// Inline sample play/stop toggle shared by the browse chart rows and the
/// collection list rows. A standalone button so it never triggers row navigation.
struct LibriVoxSampleButton: View {
    let book: LibriVoxBook
    let browseViewModel: BrowseLibriVoxViewModel
    var size: CGFloat = 22

    var body: some View {
        Button {
            if SamplePlayer.shared.isActive(for: book.id) {
                SamplePlayer.shared.stop()
            } else {
                SamplePlayer.shared.beginLoading(bookId: book.id)
                Task {
                    guard let url = await browseViewModel.fetchFirstTrackURL(for: book) else {
                        SamplePlayer.shared.stop()
                        return
                    }
                    guard SamplePlayer.shared.isActive(for: book.id) else { return }
                    SamplePlayer.shared.playSample(bookId: book.id, trackURL: url)
                }
            }
        } label: {
            Group {
                if case .loading(let id) = SamplePlayer.shared.state, id == book.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: SamplePlayer.shared.isActive(for: book.id) ? "stop.circle.fill" : "play.circle")
                        .font(.system(size: size))
                        .foregroundStyle(SamplePlayer.shared.isActive(for: book.id) ? .red : .primary)
                }
            }
            .frame(width: size + 8, height: size + 8)
        }
        .buttonStyle(.plain)
        .disabled(!NetworkMonitor.shared.isConnected && !SamplePlayer.shared.isActive(for: book.id))
    }
}

struct LibriVoxBookRow: View {
    let book: LibriVoxBook
    var browseViewModel: BrowseLibriVoxViewModel?

    var body: some View {
        HStack(spacing: 12) {
            coverThumbnail
            info
            Spacer(minLength: 0)
            if let browseViewModel {
                LibriVoxSampleButton(book: book, browseViewModel: browseViewModel)
            }
        }
        .padding(.vertical, 6)
    }

    private var coverThumbnail: some View {
        GeneratedCoverView(title: book.title)
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
