//
//  SettingsDesign.swift
//  Pageless
//
//  Shared design vocabulary for the editorial Settings sheet and its subviews.
//  Centralizes the serif/sans type tokens, eyebrow+title section header, card
//  surface, primary CTA, and other primitives reused across SettingsView,
//  AISettingsView, and ICloudSettingsView.
//

import SwiftUI
import UIKit

// MARK: - Tokens

enum SettingsDesign {
    static let cardCornerRadius: CGFloat = 18
    static let heroCornerRadius: CGFloat = 22
    static let innerCardCornerRadius: CGFloat = 14
    static let hairline: CGFloat = 0.5

    static let separator = Color(UIColor.separator)
    static let secondaryLabel = Color(UIColor.secondaryLabel)
    static let tertiaryLabel = Color(UIColor.tertiaryLabel)

    static let chipFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.06)
    })
    static let pillFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.black.withAlphaComponent(0.08)
    })

    static let systemBlue = Color(red: 10/255, green: 132/255, blue: 1)
    static let systemGreen = Color(red: 48/255, green: 209/255, blue: 88/255)

    /// Display font for editorial titles in Settings. Uses the system sans-serif so
    /// the screen matches the rest of the app's typography.
    static func displayFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Section header (eyebrow + serif title ending in a period)

struct SettingsSectionHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(SettingsDesign.secondaryLabel)
            Text(title)
                .font(SettingsDesign.displayFont(20, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.bottom, 10)
    }
}

// MARK: - Card surface

struct SettingsCard<Content: View>: View {
    var cornerRadius: CGFloat = SettingsDesign.cardCornerRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                Color.cardWhite,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - Hairline divider

struct SettingsHairline: View {
    var body: some View {
        Rectangle()
            .fill(SettingsDesign.separator)
            .frame(height: SettingsDesign.hairline)
    }
}

// MARK: - Section footer (italic-serif)

struct SettingsCardFooter: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            SettingsHairline()
            Text(text)
                .font(.system(size: 11, weight: .regular).italic())
                .foregroundStyle(SettingsDesign.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
        }
    }
}

// MARK: - Custom sheet header (serif title + black "Done" pill or back chevron)

struct SettingsSheetHeader: View {
    var title: String = "Settings"
    var titleStyle: Style = .display
    var backLabel: String?
    var onBack: (() -> Void)?
    var onDone: (() -> Void)?

    enum Style {
        case display
        case subview
    }

    var body: some View {
        HStack {
            if let backLabel, let onBack {
                Button(action: onBack) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(backLabel)
                            .font(.system(size: 15))
                            .opacity(0.7)
                    }
                    .foregroundStyle(.primary)
                }
            } else {
                Text(title)
                    .font(SettingsDesign.displayFont(26, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)
            }
            Spacer()
            if titleStyle == .subview {
                Text(title)
                    .font(SettingsDesign.displayFont(18, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(.primary)
                Spacer()
            }
            if let onDone {
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.cream)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color.primary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }
}

// MARK: - Primary blue CTA

struct SettingsPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                SettingsDesign.systemBlue.opacity(isDisabled ? 0.5 : 1),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
    }
}

// MARK: - Text link styled in system blue

struct SettingsTextLinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(SettingsDesign.systemBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Legal footer row

struct SettingsLegalLinks: View {
    var body: some View {
        HStack(spacing: 6) {
            Link("Privacy Policy", destination: LegalURLs.privacyPolicy)
            Text("·").foregroundStyle(SettingsDesign.tertiaryLabel)
            Link("Terms of Use", destination: LegalURLs.termsOfUse)
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(SettingsDesign.systemBlue)
    }
}

// MARK: - Editorial toggle row (used inside cards in subviews)

struct SettingsToggleRow<Label: View>: View {
    @Binding var isOn: Bool
    var isDisabled: Bool = false
    @ViewBuilder var label: () -> Label

    var body: some View {
        Toggle(isOn: $isOn) {
            label()
        }
        .disabled(isDisabled)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
}

struct SettingsRowLabel: View {
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(SettingsDesign.secondaryLabel)
                .lineSpacing(1)
                .multilineTextAlignment(.leading)
        }
    }
}
