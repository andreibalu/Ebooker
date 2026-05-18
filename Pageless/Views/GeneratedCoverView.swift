//
//  GeneratedCoverView.swift
//  Pageless
//

import SwiftUI
import UIKit

/// Deterministic letter-based cover template used as the default artwork for every audiobook
/// until the user replaces it via the cover picker. A curated palette is selected from the title
/// hash so each book gets a stable, distinct look across launches.
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

            ZStack {
                LinearGradient(
                    colors: [palette.top, palette.bottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Big serif initial, centered.
                Text(initial)
                    .font(.system(size: side * 0.62, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(palette.foreground)
                    .shadow(color: .black.opacity(0.15), radius: side * 0.02, x: 0, y: side * 0.01)
                    .accessibilityHidden(true)

                // Stylized title tag in the top-left.
                if side >= 60 {
                    VStack {
                        HStack {
                            Text(title)
                                .font(.system(size: max(side * 0.085, 11), weight: .medium, design: .serif))
                                .italic()
                                .foregroundStyle(palette.foreground.opacity(0.92))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, side * 0.06)
                                .padding(.vertical, side * 0.025)
                                .background(palette.tagBackground, in: Capsule())
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(side * 0.06)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .accessibilityLabel(Text("Cover for \(title)"))
    }

    private var initial: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scalar = trimmed.unicodeScalars.first(where: { CharacterSet.letters.contains($0) }) else {
            return "?"
        }
        return String(Character(scalar)).uppercased()
    }
}

// MARK: - Palette

struct GeneratedCoverPalette {
    let top: Color
    let bottom: Color
    let foreground: Color
    let tagBackground: Color

    private static let palettes: [GeneratedCoverPalette] = [
        // Indigo / purple (Pride & Prejudice in screenshot)
        GeneratedCoverPalette(
            top: Color(red: 0.34, green: 0.27, blue: 0.78),
            bottom: Color(red: 0.46, green: 0.32, blue: 0.85),
            foreground: .white,
            tagBackground: Color.black.opacity(0.30)
        ),
        // Dark navy (Moby-Dick in screenshot)
        GeneratedCoverPalette(
            top: Color(red: 0.07, green: 0.10, blue: 0.20),
            bottom: Color(red: 0.13, green: 0.17, blue: 0.30),
            foreground: .white,
            tagBackground: Color.white.opacity(0.10)
        ),
        // Forest green
        GeneratedCoverPalette(
            top: Color(red: 0.10, green: 0.32, blue: 0.24),
            bottom: Color(red: 0.16, green: 0.45, blue: 0.32),
            foreground: .white,
            tagBackground: Color.black.opacity(0.25)
        ),
        // Burgundy
        GeneratedCoverPalette(
            top: Color(red: 0.45, green: 0.10, blue: 0.18),
            bottom: Color(red: 0.62, green: 0.16, blue: 0.24),
            foreground: .white,
            tagBackground: Color.black.opacity(0.28)
        ),
        // Deep teal
        GeneratedCoverPalette(
            top: Color(red: 0.05, green: 0.30, blue: 0.36),
            bottom: Color(red: 0.10, green: 0.44, blue: 0.50),
            foreground: .white,
            tagBackground: Color.black.opacity(0.25)
        ),
        // Sepia / warm brown
        GeneratedCoverPalette(
            top: Color(red: 0.40, green: 0.26, blue: 0.18),
            bottom: Color(red: 0.55, green: 0.36, blue: 0.22),
            foreground: Color(red: 0.98, green: 0.94, blue: 0.85),
            tagBackground: Color.black.opacity(0.25)
        ),
        // Plum
        GeneratedCoverPalette(
            top: Color(red: 0.32, green: 0.13, blue: 0.36),
            bottom: Color(red: 0.50, green: 0.20, blue: 0.50),
            foreground: .white,
            tagBackground: Color.black.opacity(0.28)
        ),
        // Slate blue
        GeneratedCoverPalette(
            top: Color(red: 0.22, green: 0.30, blue: 0.46),
            bottom: Color(red: 0.32, green: 0.42, blue: 0.60),
            foreground: .white,
            tagBackground: Color.black.opacity(0.28)
        ),
        // Charcoal / graphite
        GeneratedCoverPalette(
            top: Color(red: 0.16, green: 0.16, blue: 0.18),
            bottom: Color(red: 0.26, green: 0.27, blue: 0.30),
            foreground: Color(red: 0.97, green: 0.92, blue: 0.80),
            tagBackground: Color.white.opacity(0.10)
        ),
        // Sage / olive
        GeneratedCoverPalette(
            top: Color(red: 0.28, green: 0.34, blue: 0.20),
            bottom: Color(red: 0.42, green: 0.48, blue: 0.28),
            foreground: Color(red: 0.98, green: 0.96, blue: 0.88),
            tagBackground: Color.black.opacity(0.25)
        ),
        // Sunset orange
        GeneratedCoverPalette(
            top: Color(red: 0.65, green: 0.28, blue: 0.10),
            bottom: Color(red: 0.82, green: 0.42, blue: 0.18),
            foreground: .white,
            tagBackground: Color.black.opacity(0.28)
        ),
        // Royal blue
        GeneratedCoverPalette(
            top: Color(red: 0.10, green: 0.20, blue: 0.55),
            bottom: Color(red: 0.18, green: 0.32, blue: 0.72),
            foreground: .white,
            tagBackground: Color.black.opacity(0.28)
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
