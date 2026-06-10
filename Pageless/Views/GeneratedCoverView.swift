//
//  GeneratedCoverView.swift
//  Pageless
//

import SwiftUI
import UIKit

/// Deterministic "Solid Imprint" cover template used as the default artwork for every audiobook
/// until the user replaces it via the cover picker: a full-bleed retro-pop color field with the
/// title set large in New York, and the brand glyph + UNPAGED wordmark anchored at the foot.
/// The palette is selected from the title hash so each book gets a stable look across launches.
struct GeneratedCoverView: View {
    let title: String
    let cornerRadius: CGFloat

    init(title: String, cornerRadius: CGFloat = 0) {
        self.title = title
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let palette = GeneratedCoverPalette.palette(for: title)
            // Layout ratios derived from the 380pt design comp.
            let margin = side * 0.1

            ZStack(alignment: .topLeading) {
                palette.background

                Text(title)
                    .font(.system(size: side * 0.121, weight: .medium, design: .serif))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(4)
                    .minimumScaleFactor(0.52)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, margin)
                    .padding(.top, side * 0.155)
                    .accessibilityHidden(true)

                // Brand glyph, rule and wordmark at the foot — omitted at thumbnail sizes.
                if side >= 60 {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer(minLength: 0)
                        Image(systemName: "book.pages.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(height: side * 0.095)
                            .foregroundStyle(palette.foreground)
                        Rectangle()
                            .fill(palette.foreground.opacity(0.55))
                            .frame(height: max(1, side * 0.0026))
                            .padding(.top, side * 0.047)
                        Text("UNPAGED")
                            .font(.system(size: side * 0.0395, weight: .regular, design: .serif))
                            .tracking(side * 0.0118)
                            .foregroundStyle(palette.foreground.opacity(0.78))
                            .padding(.top, side * 0.026)
                    }
                    .padding(.horizontal, margin)
                    .padding(.bottom, side * 0.05)
                    .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .accessibilityLabel(Text("Cover for \(title)"))
    }
}

// MARK: - Palette

struct GeneratedCoverPalette {
    let background: Color
    let foreground: Color

    /// Retro Pop family — bold 70s brights. Cream text on every field except mustard,
    /// which flips to a dark cocoa foreground for contrast.
    private static let cream = Color(red: 0.984, green: 0.953, blue: 0.894)   // #FBF3E4

    private static let palettes: [GeneratedCoverPalette] = [
        // Tangerine
        GeneratedCoverPalette(
            background: Color(red: 0.851, green: 0.424, blue: 0.184),         // #D96C2F
            foreground: cream
        ),
        // Mustard (dark foreground)
        GeneratedCoverPalette(
            background: Color(red: 0.851, green: 0.631, blue: 0.231),         // #D9A13B
            foreground: Color(red: 0.239, green: 0.173, blue: 0.071)          // #3D2C12
        ),
        // Avocado
        GeneratedCoverPalette(
            background: Color(red: 0.478, green: 0.549, blue: 0.180),         // #7A8C2E
            foreground: cream
        ),
        // Burnt orange
        GeneratedCoverPalette(
            background: Color(red: 0.761, green: 0.306, blue: 0.122),         // #C24E1F
            foreground: cream
        ),
        // Teal pop
        GeneratedCoverPalette(
            background: Color(red: 0.122, green: 0.541, blue: 0.478),         // #1F8A7A
            foreground: cream
        ),
        // Raspberry
        GeneratedCoverPalette(
            background: Color(red: 0.722, green: 0.227, blue: 0.369),         // #B83A5E
            foreground: cream
        ),
        // Cobalt
        GeneratedCoverPalette(
            background: Color(red: 0.141, green: 0.337, blue: 0.702),         // #2456B3
            foreground: cream
        ),
        // Chocolate
        GeneratedCoverPalette(
            background: Color(red: 0.420, green: 0.243, blue: 0.118),         // #6B3E1E
            foreground: cream
        )
    ]

    static func palette(for title: String) -> GeneratedCoverPalette {
        let key = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return palettes[0] }
        // FNV-1a 32-bit — stable across launches (unlike Swift's String.hashValue).
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        let idx = Int(hash % UInt32(palettes.count))
        return palettes[idx]
    }
}

// MARK: - UIImage rendering

extension GeneratedCoverView {
    /// Renders the generated cover to a UIImage at the requested size.
    /// Used for MPNowPlayingInfoCenter and CarPlay artwork where SwiftUI views cannot be embedded.
    @MainActor
    static func renderImage(title: String, side: CGFloat = 600) -> UIImage? {
        let view = GeneratedCoverView(title: title, cornerRadius: 0)
            .frame(width: side, height: side)
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

#Preview {
    VStack(spacing: 16) {
        GeneratedCoverView(title: "Pride and Prejudice", cornerRadius: 16)
            .frame(width: 180, height: 180)
        GeneratedCoverView(title: "Moby-Dick", cornerRadius: 16)
            .frame(width: 180, height: 180)
        GeneratedCoverView(title: "The Adventures of Sherlock Holmes", cornerRadius: 16)
            .frame(width: 180, height: 180)
    }
    .padding()
    .background(Color.cream)
}
