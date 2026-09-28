//
//  ABSComponents.swift
//  Pageless
//
//  Shared primitives for the Audiobookshelf screens. The type scale mirrors the Free Books
//  `FBType` sizes (10 / 12 / 15 / 19) but is expressed as text styles so it follows Dynamic Type.
//

import SwiftUI

enum ABSType {
    static func eyebrow() -> Font { .caption2.weight(.semibold) }
    static func body() -> Font { .caption }
    static func title(_ weight: Font.Weight = .semibold) -> Font { .system(.subheadline, design: .serif, weight: weight) }
    static func headline() -> Font { .system(.title3, design: .serif, weight: .semibold) }
    static func display() -> Font { .system(.title, design: .serif, weight: .semibold) }
    static let hairline = Color.primary.opacity(0.18)
}

/// Small-caps metadata line ("AUDIOBOOKSHELF · HOST").
struct ABSEyebrow: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text.uppercased())
            .font(ABSType.eyebrow())
            .tracking(1.2)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(2)
    }
}

/// App-standard section header: semibold subheadline + hairline rule.
struct ABSSectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Rectangle()
                .fill(ABSType.hairline)
                .frame(height: 0.5)
        }
    }
}

/// Square cover (ABS libraries default to 1:1). Fetched through `ABSCoverStore` with the auth
/// header; items with no cover, or failed fetches, fall through to `GeneratedCoverView`.
struct ABSCoverView: View {
    let itemID: String
    let title: String
    let hasCover: Bool
    var cornerRadius: CGFloat = 8
    var client: AudiobookshelfClient = ABSAccount.shared.client

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = image ?? ABSCoverStore.shared.cachedImage(itemID: itemID) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    GeneratedCoverView(title: title)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
            .accessibilityHidden(true)
            .task(id: itemID) {
                guard hasCover, image == nil else { return }
                image = await ABSCoverStore.shared.image(itemID: itemID, client: client)
            }
    }
}

/// Thin amber listening-progress rule under a cover.
struct ABSProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(Color.amber)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// Placeholder cover for the loading state. Pulses unless Reduce Motion is on.
struct ABSSkeletonCover: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .aspectRatio(1, contentMode: .fit)
            RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)).frame(height: 10)
            RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.06)).frame(width: 50, height: 8)
        }
        .opacity(dim ? 0.5 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityHidden(true)
    }
}

/// Centered empty/error state with a single action.
struct ABSStateView: View {
    let eyebrow: String
    let title: String
    let message: String
    var actionTitle: String?
    var actionIdentifier: String = "abs.state.action"
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            ABSEyebrow(text: eyebrow)
            Text(title)
                .font(ABSType.headline())
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(ABSPrimaryButtonStyle(fullWidth: false))
                    .padding(.top, 8)
                    .accessibilityIdentifier(actionIdentifier)
            }
        }
        .frame(maxWidth: 340)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// The one amber action on a screen.
struct ABSPrimaryButtonStyle: ButtonStyle {
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 50)
            .background(Color.amber.opacity(isEnabled ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(AppMotion.press, value: configuration.isPressed)
    }
}

/// Quiet secondary action: outlined, no fill, no amber.
struct ABSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
