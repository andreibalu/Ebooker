//
//  EqualizerSheet.swift
//  Pageless
//

import SwiftUI

struct EqualizerSheet: View {
    @EnvironmentObject private var equalizer: AudioEqualizerService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    enableCard
                    amplifierCard
                    presetsCard
                    bandsCard
                    resetButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollContentBackground(.hidden)
            .background(Color.cream.ignoresSafeArea())
            .navigationTitle("Equalizer")
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
    }

    // MARK: - Enable

    private var enableCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Equalizer")
                    .font(.subheadline.weight(.semibold))
                Text("Adjust tone and boost quiet books")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Equalizer", isOn: Binding(
                get: { equalizer.isEnabled },
                set: { equalizer.setEnabled($0) }
            ))
            .labelsHidden()
            .tint(Color.primary.opacity(0.7))
        }
        .padding(16)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - Amplifier

    private var amplifierCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Volume Boost")
                        .font(.subheadline.weight(.semibold))
                    Text("Override the max volume for quiet books")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("+\(Int(equalizer.preampDB)) dB")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Slider(
                value: Binding(
                    get: { equalizer.preampDB },
                    set: { equalizer.setPreamp($0) }
                ),
                in: EqualizerConfiguration.preampRange,
                step: 1
            )
            .tint(Color.primary.opacity(0.7))

            if equalizer.preampDB > 9 {
                Label("High boost may distort very quiet passages.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .animation(.easeInOut(duration: 0.2), value: equalizer.preampDB > 9)
    }

    // MARK: - Presets

    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preset")
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EqualizerPreset.allCases) { preset in
                        Button {
                            equalizer.applyPreset(preset)
                        } label: {
                            Text(preset.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    preset == equalizer.preset
                                        ? Color.primary.opacity(0.1)
                                        : Color.cardWhite,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                                .foregroundStyle(.primary)
                                .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .opacity(equalizer.isEnabled ? 1.0 : 0.4)
        .disabled(!equalizer.isEnabled)
    }

    // MARK: - Bands

    private var bandsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual EQ")
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .center, spacing: 6) {
                ForEach(EqualizerBand.allCases) { band in
                    bandSlider(for: band)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .opacity(equalizer.isEnabled ? 1.0 : 0.4)
        .disabled(!equalizer.isEnabled)
    }

    private func bandSlider(for band: EqualizerBand) -> some View {
        let index = band.rawValue
        let gain = index < equalizer.bandGainsDB.count ? equalizer.bandGainsDB[index] : 0
        let sliderBinding = Binding<Double>(
            get: { index < equalizer.bandGainsDB.count ? equalizer.bandGainsDB[index] : 0 },
            set: { equalizer.setBandGain(band, dB: $0) }
        )

        return VStack(spacing: 6) {
            Text(gainLabel(gain))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 32)

            Slider(
                value: sliderBinding,
                in: EqualizerConfiguration.bandRange,
                step: 1
            )
            .tint(Color.primary.opacity(0.7))
            .rotationEffect(.degrees(-90))
            .frame(width: 180)
            .frame(width: 40, height: 180)
            .clipped()

            Text(band.shortLabel)
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)
                .frame(minWidth: 32)

            Text("Hz")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func gainLabel(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded > 0 { return "+\(rounded)" }
        return "\(rounded)"
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button {
            equalizer.reset()
        } label: {
            Text("Reset to Flat")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
