//
//  SpotlightOverlayView.swift
//  Pageless
//

import SwiftUI

// MARK: - Preference Key

struct SpotlightAnchorKey: PreferenceKey {
    static let defaultValue: [OnboardingStep: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [OnboardingStep: Anchor<CGRect>],
        nextValue: () -> [OnboardingStep: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - View Modifier

extension View {
    func spotlightTarget(_ step: OnboardingStep) -> some View {
        anchorPreference(key: SpotlightAnchorKey.self, value: .bounds) { anchor in
            [step: anchor]
        }
    }
}

// MARK: - Mask Shape

private struct SpotlightMaskShape: Shape {
    var highlight: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(highlight.origin.x, highlight.origin.y),
                AnimatablePair(highlight.size.width, highlight.size.height)
            )
        }
        set {
            highlight = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(
            in: highlight,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return path
    }
}

// MARK: - Overlay

struct SpotlightOverlayView: View {
    let highlightFrame: CGRect
    let step: OnboardingStep
    let deviceSupportsOnboardingAI: Bool
    let requiresIOSUpgrade: Bool
    let totalSteps: Int
    let currentIndex: Int
    let onNext: () -> Void
    let onBack: (() -> Void)?
    let onSkip: () -> Void

    private let padding: CGFloat = 10
    private let cornerRadius: CGFloat = 14
    private let tooltipWidth: CGFloat = 280

    private var paddedFrame: CGRect {
        highlightFrame.insetBy(dx: -padding, dy: -padding)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                // Dark mask with cutout
                SpotlightMaskShape(highlight: paddedFrame, cornerRadius: cornerRadius)
                    .fill(style: FillStyle(eoFill: true))
                    .foregroundStyle(.black.opacity(0.62))
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.35), value: highlightFrame)

                // Tooltip
                tooltipCard(screenSize: size)
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    private func tooltipCard(screenSize: CGSize) -> some View {
        let isAbove = paddedFrame.midY > screenSize.height / 2
        let gap: CGFloat = 24
        let tooltipY: CGFloat = isAbove
            ? paddedFrame.minY - gap
            : paddedFrame.maxY + gap

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(step.title(deviceSupportsOnboardingAI: deviceSupportsOnboardingAI, requiresIOSUpgrade: requiresIOSUpgrade))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(step.body(deviceSupportsOnboardingAI: deviceSupportsOnboardingAI, requiresIOSUpgrade: requiresIOSUpgrade))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let onBack {
                    Button { onBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                }

                Button("Skip") { onSkip() }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(currentIndex + 1) of \(totalSteps)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button(step.buttonLabel) { onNext() }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.primary, in: Capsule())
                    .foregroundStyle(Color(UIColor.systemBackground))
            }
        }
        .padding(14)
        .frame(width: tooltipWidth)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 16, y: 4)
        .position(
            x: clamp(
                paddedFrame.midX,
                min: tooltipWidth / 2 + 16,
                max: screenSize.width - tooltipWidth / 2 - 16
            ),
            y: isAbove
                ? tooltipY - tooltipEstimatedHeight / 2
                : tooltipY + tooltipEstimatedHeight / 2
        )
        .animation(.easeInOut(duration: 0.35), value: highlightFrame)
    }

    private var tooltipEstimatedHeight: CGFloat { 160 }

    private func clamp(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        Swift.max(minVal, Swift.min(maxVal, value))
    }
}

// MARK: - Convenience overlay modifier

extension View {
    /// Attach this to a root container to render the spotlight overlay for the given onboarding manager.
    func spotlightOverlay(onboarding: OnboardingManager, totalPhaseSteps: Int, currentPhaseIndex: Int) -> some View {
        overlayPreferenceValue(SpotlightAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let step = onboarding.currentStep, let anchor = anchors[step] {
                    let frame = proxy[anchor]
                    SpotlightOverlayView(
                        highlightFrame: frame,
                        step: step,
                        deviceSupportsOnboardingAI: onboarding.deviceSupportsOnboardingAI,
                        requiresIOSUpgrade: onboarding.requiresIOSUpgradeForAI,
                        totalSteps: totalPhaseSteps,
                        currentIndex: currentPhaseIndex,
                        onNext: { onboarding.advance() },
                        onBack: currentPhaseIndex > 0 ? { onboarding.goBack() } : nil,
                        onSkip: { onboarding.skipOnboarding() }
                    )
                    .animation(.easeInOut(duration: 0.25), value: step)
                }
            }
            .ignoresSafeArea()
        }
    }
}
