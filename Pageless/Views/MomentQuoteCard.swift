//
//  MomentQuoteCard.swift
//  Pageless
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Sendable share payload

struct MomentQuoteCardPayload: Sendable {
    let bookTitle: String
    let author: String
    let coverArtData: Data?
    let quoteLine: String?
    let label: String
    let note: String?
    let chapterTitle: String?
    let timestamp: String

    init(
        bookTitle: String,
        author: String,
        coverArtData: Data?,
        quoteLine: String?,
        label: String,
        note: String?,
        chapterTitle: String?,
        timestamp: String
    ) {
        self.bookTitle = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        self.coverArtData = coverArtData
        let trimmedQuote = quoteLine?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.quoteLine = (trimmedQuote?.isEmpty ?? true) ? nil : trimmedQuote
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
        let trimmedChapter = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterTitle = (trimmedChapter?.isEmpty ?? true) ? nil : trimmedChapter
        self.timestamp = timestamp
    }

    @MainActor
    init(moment: Moment, audiobook: Audiobook) {
        let tracks = audiobook.sortedTracks
        let chapter = tracks.indices.contains(moment.trackIndex)
            ? tracks[moment.trackIndex].displayTitle
            : nil
        self.init(
            bookTitle: audiobook.title,
            author: audiobook.author,
            coverArtData: audiobook.coverArtData,
            quoteLine: moment.quoteLine,
            label: moment.label,
            note: moment.notes,
            chapterTitle: chapter,
            timestamp: TimeFormatter.clockString(seconds: moment.time)
        )
    }

    var previewTitle: String {
        if !label.isEmpty && !bookTitle.isEmpty {
            return "\(label) — \(bookTitle)"
        }
        return !label.isEmpty ? label : bookTitle
    }
}

// MARK: - Lazy Transferable PNG

/// Renders the editorial quote card PNG lazily inside the transfer closure, never during `body`.
struct MomentQuoteCardImage: Transferable, Sendable {
    let payload: MomentQuoteCardPayload

    init(payload: MomentQuoteCardPayload) {
        self.payload = payload
    }

    @MainActor
    init(moment: Moment, audiobook: Audiobook) {
        self.payload = MomentQuoteCardPayload(moment: moment, audiobook: audiobook)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            try await item.renderPNGData()
        }
        // Without a name the share sheet shows the temp file's ".com.apple.Foundation.NSI…" name.
        .suggestedFileName("Unpaged Moment.png")
    }

    @MainActor
    func renderPNGData() throws -> Data {
        let card = MomentQuoteCardView(payload: payload)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let uiImage = renderer.uiImage,
              let data = uiImage.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}

// MARK: - Editorial Quote Card View (explicit warm-cream light palette, pinned Dynamic Type)

struct MomentQuoteCardView: View {
    let payload: MomentQuoteCardPayload

    // Explicit non-dynamic light colors so off-screen ImageRenderer never resolves dark-mode UIColors.
    private static let creamBG = Color(red: 0.97, green: 0.955, blue: 0.93)
    private static let cardSurface = Color(red: 1.0, green: 0.99, blue: 0.97)
    private static let primaryInk = Color(red: 0.12, green: 0.11, blue: 0.10)
    private static let secondaryInk = Color(red: 0.42, green: 0.40, blue: 0.37)
    private static let amberAccent = Color(red: 0.800, green: 0.525, blue: 0.196)
    private static let hairline = Color(red: 0.12, green: 0.11, blue: 0.10).opacity(0.10)

    private var positionSubtitle: String {
        if let chapter = payload.chapterTitle {
            return "\(chapter) · \(payload.timestamp)"
        }
        return payload.timestamp
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Book header
            HStack(alignment: .center, spacing: 14) {
                coverArtwork
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Self.hairline, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(payload.bookTitle)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(Self.primaryInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !payload.author.isEmpty {
                        Text(payload.author)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(Self.secondaryInk)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            // Editorial body card
            VStack(alignment: .leading, spacing: 12) {
                if let quote = payload.quoteLine {
                    Text("\u{201C}")
                        .font(.system(size: 40, weight: .semibold, design: .serif))
                        .foregroundStyle(Self.amberAccent)
                        .frame(height: 22, alignment: .topLeading)
                        .padding(.bottom, -4)

                    Text(quote)
                        .font(.system(size: 20, weight: .regular, design: .serif).italic())
                        .foregroundStyle(Self.primaryInk)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(payload.label)
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(Self.primaryInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let note = payload.note {
                        Text(note)
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundStyle(Self.secondaryInk)
                            .lineSpacing(3.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(positionSubtitle)
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Self.secondaryInk)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Self.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Self.hairline, lineWidth: 1)
            )
            .padding(.top, 18)

            Rectangle()
                .fill(Self.hairline)
                .frame(height: 1)
                .padding(.top, 18)

            // Brand footer
            HStack(spacing: 8) {
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.amberAccent)
                Text("UNPAGED")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .tracking(2.4)
                    .foregroundStyle(Self.primaryInk)
                Spacer()
                Text("Saved Moment")
                    .font(.system(size: 11))
                    .foregroundStyle(Self.secondaryInk)
            }
            .padding(.top, 12)
        }
        .padding(24)
        .frame(width: 360)
        .background(Self.creamBG)
    }

    @ViewBuilder
    private var coverArtwork: some View {
        if let data = payload.coverArtData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            GeneratedCoverView(title: payload.bookTitle, cornerRadius: 10)
        }
    }
}

#Preview("With Quote") {
    MomentQuoteCardView(
        payload: MomentQuoteCardPayload(
            bookTitle: "Pride and Prejudice",
            author: "Jane Austen",
            coverArtData: nil,
            quoteLine: "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
            label: "Opening line",
            note: "Classic opening statement.",
            chapterTitle: "Chapter 1",
            timestamp: "00:42"
        )
    )
}

#Preview("Label and Note") {
    MomentQuoteCardView(
        payload: MomentQuoteCardPayload(
            bookTitle: "Moby-Dick",
            author: "Herman Melville",
            coverArtData: nil,
            quoteLine: nil,
            label: "Setting sail from Nantucket",
            note: "Ishmael reflects on why he takes to the sea whenever his spirits grow grim.",
            chapterTitle: "Chapter 1: Loomings",
            timestamp: "03:15"
        )
    )
}
