//
//  AudioEqualizerService.swift
//  Pageless
//

import AVFoundation
import Combine
import Foundation
import SwiftData

/// Per-book audio equalizer + amplifier. Owns a shared `MTAudioProcessingTap` storage block that
/// survives across `AVPlayerItem` swaps; audio mixes attached to each new item point to the same
/// storage, so gain/band edits apply live without recreating the player.
@MainActor
final class AudioEqualizerService: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var preset: EqualizerPreset = .flat
    @Published private(set) var preampDB: Double = 0
    @Published private(set) var bandGainsDB: [Double] = EqualizerPreset.flat.bandGainsDB

    private weak var boundAudiobook: Audiobook?
    private var modelContext: ModelContext?
    private let tapContext: EqualizerTapContext

    init() {
        self.tapContext = EqualizerTapContext()
        refreshTapCoefficients()
    }

    deinit {
        tapContext.release()
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Loads the given audiobook's saved config into the published state and pushes to the tap.
    /// Pass `nil` to unbind (leaves prior state on the tap until a new book binds).
    func bind(to audiobook: Audiobook?) {
        boundAudiobook = audiobook
        let config = audiobook?.equalizerConfiguration ?? .flat
        isEnabled = config.isEnabled
        preset = config.preset
        preampDB = config.preampDB
        bandGainsDB = config.bandGainsDB
        refreshTapCoefficients()
    }

    // MARK: - User actions

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        persist()
        refreshTapCoefficients()
    }

    func applyPreset(_ newPreset: EqualizerPreset) {
        preset = newPreset
        if newPreset != .custom {
            bandGainsDB = newPreset.bandGainsDB
        }
        persist()
        refreshTapCoefficients()
    }

    func setBandGain(_ band: EqualizerBand, dB: Double) {
        var gains = bandGainsDB
        let clamped = min(max(dB, EqualizerConfiguration.bandRange.lowerBound),
                          EqualizerConfiguration.bandRange.upperBound)
        guard band.rawValue < gains.count else { return }
        gains[band.rawValue] = clamped
        bandGainsDB = gains
        if preset != .custom {
            preset = .custom
        }
        persist()
        refreshTapCoefficients()
    }

    func setPreamp(_ dB: Double) {
        let clamped = min(max(dB, EqualizerConfiguration.preampRange.lowerBound),
                          EqualizerConfiguration.preampRange.upperBound)
        guard preampDB != clamped else { return }
        preampDB = clamped
        persist()
        refreshTapCoefficients()
    }

    /// Resets to flat preset, 0 dB preamp. Leaves `isEnabled` untouched.
    func reset() {
        preset = .flat
        bandGainsDB = EqualizerPreset.flat.bandGainsDB
        preampDB = 0
        persist()
        refreshTapCoefficients()
    }

    // MARK: - Audio mix integration

    /// Creates an `AVAudioMix` that routes audio through this service's processing tap. Returns
    /// `nil` if the asset has no audio track. Call on each new `AVPlayerItem`.
    func makeAudioMix(for asset: AVAsset) async -> AVAudioMix? {
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            return nil
        }
        guard let audioTrack = tracks.first else { return nil }

        let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
        guard let tap = EqualizerTap.make(context: tapContext) else { return nil }
        parameters.audioTapProcessor = tap

        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    // MARK: - Private

    private func currentConfiguration() -> EqualizerConfiguration {
        var config = EqualizerConfiguration(
            isEnabled: isEnabled,
            preset: preset,
            preampDB: preampDB,
            bandGainsDB: bandGainsDB
        )
        config.clamp()
        return config
    }

    private func persist() {
        guard let audiobook = boundAudiobook else { return }
        audiobook.equalizerConfiguration = currentConfiguration()
        try? modelContext?.save()
    }

    private func refreshTapCoefficients() {
        tapContext.update(with: currentConfiguration())
    }
}
