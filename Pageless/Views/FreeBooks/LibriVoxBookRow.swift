//
//  LibriVoxBookRow.swift
//  Pageless
//

import SwiftUI

struct LibriVoxBookRow: View {
    let book: LibriVoxBook

    var body: some View {
        HStack(spacing: 12) {
            coverThumbnail
            info
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private var coverThumbnail: some View {
        AsyncImage(url: book.coverThumbnailURL) { phase in
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
