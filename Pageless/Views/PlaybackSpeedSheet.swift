//
//  PlaybackSpeedSheet.swift
//  Pageless
//

import SwiftUI
import UIKit

struct PlaybackSpeedSheet: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectionHaptic = UISelectionFeedbackGenerator()
    private let presets: [Double] = [0.8, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    var body: some View {
        NavigationStack {
            ViewThatFits(in: .vertical) {
                VStack(spacing: 16) {
                    speedControlCard
                    presetsStrip
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView {
                    VStack(spacing: 16) {
                        speedControlCard
                        presetsStrip
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.cream.ignoresSafeArea())
            .navigationTitle("Playback Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.cream, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            selectionHaptic.prepare()
        }
    }

    // MARK: - Speed Control Card

    private var speedControlCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(PlayerQuickActionDisplay.playbackRateSymbolTitle(for: player.playbackRate))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("speed.readout")

                Text(remainingCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("speed.remaining")
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: player.playbackRate)

            HStack(spacing: 14) {
                stepButton(
                    systemImage: "minus",
                    label: "Decrease speed",
                    identifier: "speed.decrement",
                    disabled: player.playbackRate <= AudioPlayerManager.minPlaybackRate + 0.001
                ) {
                    step(by: -AudioPlayerManager.playbackRateStep)
                }

                Slider(
                    value: Binding(
                        get: { player.playbackRate },
                        set: { newValue in
                            let step = AudioPlayerManager.playbackRateStep
                            let snapped = (newValue / step).rounded() * step
                            let normalized = AudioPlayerManager.normalizedPlaybackRate(snapped)
                            if abs(normalized - player.playbackRate) >= 0.001 {
                                selectionHaptic.selectionChanged()
                                player.setPlaybackRate(normalized, persist: false)
                            }
                        }
                    ),
                    in: AudioPlayerManager.minPlaybackRate...AudioPlayerManager.maxPlaybackRate,
                    onEditingChanged: { editing in
                        if !editing { player.setPlaybackRate(player.playbackRate) }
                    }
                )
                .tint(Color.amber)
                .accessibilityLabel("Playback speed")
                .accessibilityValue(PlayerQuickActionDisplay.playbackRateSymbolTitle(for: player.playbackRate))
                .accessibilityIdentifier("speed.slider")

                stepButton(
                    systemImage: "plus",
                    label: "Increase speed",
                    identifier: "speed.increment",
                    disabled: player.playbackRate >= AudioPlayerManager.maxPlaybackRate - 0.001
                ) {
                    step(by: AudioPlayerManager.playbackRateStep)
                }
            }

            HStack {
                Text("0.5×")
                Spacer()
                Text("3×")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 54)
        }
        .padding(18)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private func stepButton(
        systemImage: String,
        label: String,
        identifier: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(disabled ? Color.secondary.opacity(0.4) : Color.primary)
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.07), in: Circle())
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.94))
        .disabled(disabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Presets Grid

    private let presetColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var presetsStrip: some View {
        LazyVGrid(columns: presetColumns, spacing: 8) {
            ForEach(presets, id: \.self) { rate in
                let isSelected = abs(player.playbackRate - rate) < 0.005
                Button {
                    selectionHaptic.selectionChanged()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        player.setPlaybackRate(rate)
                    }
                } label: {
                    Text(PlayerQuickActionDisplay.playbackRateSymbolTitle(for: rate))
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            isSelected ? Color.primary : Color.cardWhite,
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? Color.cream : Color.primary)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isSelected ? Color.clear : Color.primary.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(TactileScaleButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("speed.preset.\(Int((rate * 100).rounded()))")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    // MARK: - Helpers

    private func step(by delta: Double) {
        let next = AudioPlayerManager.normalizedPlaybackRate(player.playbackRate + delta)
        guard abs(next - player.playbackRate) >= 0.001 else { return }
        selectionHaptic.selectionChanged()
        player.setPlaybackRate(next)
    }

    private var remainingCaption: String {
        let rawRemaining = player.currentBookRemainingDuration
        guard rawRemaining > 0 else {
            return abs(player.playbackRate - 1.0) < 0.005 ? "Normal speed" : "Custom speed"
        }
        let adjusted = TimeFormatter.speedAdjustedSeconds(rawRemaining, rate: player.playbackRate)
        let summary = TimeFormatter.durationSummary(seconds: adjusted)
        if abs(player.playbackRate - 1.0) < 0.005 {
            return "\(summary) left in book · normal speed"
        }
        return "\(summary) left in book at \(PlayerQuickActionDisplay.playbackRateSymbolTitle(for: player.playbackRate))"
    }
}
