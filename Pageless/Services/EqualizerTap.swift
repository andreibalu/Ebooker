//
//  EqualizerTap.swift
//  Pageless
//
//  C-level MTAudioProcessingTap implementing 5-band peaking EQ + preamp with a soft tanh limiter.
//  Callbacks run on a realtime audio thread. TapState is heap-allocated and its pointer is shared
//  across every AVPlayerItem mix; main-thread updates protect coefficients with an `os_unfair_lock`.
//

import AVFoundation
import Darwin
import Foundation
import MediaToolbox

// MARK: - Filter math

private let bandCount = EqualizerBand.allCases.count
private let maxChannels = 8

private struct BiquadCoefficients {
    var b0: Float
    var b1: Float
    var b2: Float
    var a1: Float
    var a2: Float

    static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
}

private struct BiquadDelay {
    var x1: Float = 0
    var x2: Float = 0
    var y1: Float = 0
    var y2: Float = 0
}

/// RBJ cookbook peaking EQ coefficients, normalized by a0. Q = 1.0 gives a ~1-octave bell.
private func makePeakingCoefficients(
    frequencyHz: Double,
    gainDB: Double,
    q: Double,
    sampleRate: Double
) -> BiquadCoefficients {
    guard sampleRate > 0, frequencyHz > 0, frequencyHz < sampleRate * 0.5 else {
        return .identity
    }
    let w0 = 2.0 * .pi * frequencyHz / sampleRate
    let cosW0 = cos(w0)
    let sinW0 = sin(w0)
    let alpha = sinW0 / (2.0 * q)
    let A = pow(10.0, gainDB / 40.0)

    let b0 = 1 + alpha * A
    let b1 = -2 * cosW0
    let b2 = 1 - alpha * A
    let a0 = 1 + alpha / A
    let a1 = -2 * cosW0
    let a2 = 1 - alpha / A

    return BiquadCoefficients(
        b0: Float(b0 / a0),
        b1: Float(b1 / a0),
        b2: Float(b2 / a0),
        a1: Float(a1 / a0),
        a2: Float(a2 / a0)
    )
}

// MARK: - Shared state

/// Heap-allocated block shared between main thread (writers) and the audio thread (reader).
/// Coefficients are small and written atomically under `lock`; delay state is audio-thread-only.
final class TapState: @unchecked Sendable {
    var lock = os_unfair_lock()

    // Writer-controlled (main thread under lock).
    var enabled: Bool = false
    var preampLinear: Float = 1.0
    fileprivate var coefficients: [BiquadCoefficients] = Array(repeating: .identity, count: bandCount)

    // Reader-controlled (audio thread, no lock needed — single-producer single-consumer).
    var sampleRate: Double = 44_100
    var channelCount: Int = 2
    fileprivate var delays: [[BiquadDelay]] = Array(
        repeating: Array(repeating: BiquadDelay(), count: bandCount),
        count: 2
    )

    // Pending coefficients for when sample rate changes in `prepare`.
    var pendingGainsDB: [Double] = Array(repeating: 0, count: bandCount)
}

/// Allocates/deallocates a `TapState` and publishes updates to it. The class itself carries no
/// actor isolation — `update` is called from the main thread by `AudioEqualizerService`, while
/// the audio thread reads the same storage through the tap's C callbacks.
final class EqualizerTapContext: @unchecked Sendable {
    fileprivate let pointer: UnsafeMutablePointer<TapState>

    init() {
        let heap = UnsafeMutablePointer<TapState>.allocate(capacity: 1)
        heap.initialize(to: TapState())
        self.pointer = heap
    }

    func release() {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }

    /// Recompute coefficients from the given configuration and publish under lock.
    func update(with config: EqualizerConfiguration) {
        let enabled = config.isEnabled
        let preamp = Float(pow(10.0, config.preampDB / 20.0))
        let gains = config.bandGainsDB

        os_unfair_lock_lock(&pointer.pointee.lock)
        let sampleRate = pointer.pointee.sampleRate
        var newCoeffs: [BiquadCoefficients] = []
        newCoeffs.reserveCapacity(bandCount)
        for (index, band) in EqualizerBand.allCases.enumerated() {
            let gain = index < gains.count ? gains[index] : 0
            newCoeffs.append(
                makePeakingCoefficients(
                    frequencyHz: band.frequencyHz,
                    gainDB: gain,
                    q: 1.0,
                    sampleRate: sampleRate
                )
            )
        }
        pointer.pointee.enabled = enabled
        pointer.pointee.preampLinear = preamp
        pointer.pointee.coefficients = newCoeffs
        pointer.pointee.pendingGainsDB = gains
        os_unfair_lock_unlock(&pointer.pointee.lock)
    }
}

// MARK: - Tap factory

enum EqualizerTap {
    /// Creates a retained MTAudioProcessingTap wired to this context's shared state.
    /// The returned tap is owned by the caller (assign to `audioTapProcessor` — AVFoundation will
    /// release it when the mix is destroyed).
    static func make(context: EqualizerTapContext) -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(context.pointer),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )

        var tapRef: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tapRef
        )
        guard status == noErr, let tap = tapRef else { return nil }
        return tap
    }
}

// MARK: - C callbacks

private func tapInit(
    tap: MTAudioProcessingTap,
    clientInfo: UnsafeMutableRawPointer?,
    tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func tapFinalize(tap: MTAudioProcessingTap) {
    // TapState is owned by EqualizerTapContext and outlives the tap. Nothing to free here.
}

private func tapPrepare(
    tap: MTAudioProcessingTap,
    maxFrames: CMItemCount,
    processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    let statePtr = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: TapState.self)
    let format = processingFormat.pointee
    let channels = max(1, Int(min(format.mChannelsPerFrame, UInt32(maxChannels))))
    let sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44_100
    let delays = Array(
        repeating: Array(repeating: BiquadDelay(), count: bandCount),
        count: channels
    )

    // Recompute coefficients for the new sample rate using the most-recent pending gains.
    os_unfair_lock_lock(&statePtr.pointee.lock)
    statePtr.pointee.sampleRate = sampleRate
    statePtr.pointee.channelCount = channels
    statePtr.pointee.delays = delays
    let gains = statePtr.pointee.pendingGainsDB
    var newCoeffs: [BiquadCoefficients] = []
    newCoeffs.reserveCapacity(bandCount)
    for (index, band) in EqualizerBand.allCases.enumerated() {
        let gain = index < gains.count ? gains[index] : 0
        newCoeffs.append(
            makePeakingCoefficients(
                frequencyHz: band.frequencyHz,
                gainDB: gain,
                q: 1.0,
                sampleRate: sampleRate
            )
        )
    }
    statePtr.pointee.coefficients = newCoeffs
    os_unfair_lock_unlock(&statePtr.pointee.lock)
}

private func tapUnprepare(tap: MTAudioProcessingTap) {
    // No realtime resources to free; delay state is reset on next prepare.
}

private func tapProcess(
    tap: MTAudioProcessingTap,
    numberFrames: CMItemCount,
    flags: MTAudioProcessingTapFlags,
    bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    var framesProvided: CMItemCount = 0
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        flagsOut,
        nil,
        &framesProvided
    )
    numberFramesOut.pointee = framesProvided
    guard status == noErr else { return }

    let statePtr = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: TapState.self)

    // Snapshot writer-controlled values under lock (tiny copy).
    os_unfair_lock_lock(&statePtr.pointee.lock)
    let enabled = statePtr.pointee.enabled
    let preamp = statePtr.pointee.preampLinear
    let coeffs = statePtr.pointee.coefficients
    os_unfair_lock_unlock(&statePtr.pointee.lock)

    guard enabled else { return }

    let bufferList = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    let channelCount = statePtr.pointee.channelCount
    let frames = Int(framesProvided)

    // Typical AVPlayer tap format: non-interleaved Float32, one AudioBuffer per channel.
    for (bufferIndex, buffer) in bufferList.enumerated() {
        guard bufferIndex < channelCount else { break }
        guard let raw = buffer.mData else { continue }
        let samplesPerBuffer = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let buffered = buffer.mNumberChannels > 1
            ? samplesPerBuffer / Int(buffer.mNumberChannels)
            : samplesPerBuffer
        let frameCount = min(frames, buffered)
        let samples = raw.assumingMemoryBound(to: Float.self)

        let interleavedChannels = Int(buffer.mNumberChannels)
        if interleavedChannels <= 1 {
            processChannel(
                samples: samples,
                frameCount: frameCount,
                stride: 1,
                preamp: preamp,
                coeffs: coeffs,
                delaysPtr: &statePtr.pointee.delays[bufferIndex]
            )
        } else {
            // Interleaved within a single buffer — process each interleaved channel separately.
            for channelOffset in 0..<interleavedChannels {
                let delayIndex = min(channelOffset, statePtr.pointee.delays.count - 1)
                processChannel(
                    samples: samples.advanced(by: channelOffset),
                    frameCount: frameCount,
                    stride: interleavedChannels,
                    preamp: preamp,
                    coeffs: coeffs,
                    delaysPtr: &statePtr.pointee.delays[delayIndex]
                )
            }
        }
    }
}

@inline(__always)
private func processChannel(
    samples: UnsafeMutablePointer<Float>,
    frameCount: Int,
    stride: Int,
    preamp: Float,
    coeffs: [BiquadCoefficients],
    delaysPtr: UnsafeMutablePointer<[BiquadDelay]>
) {
    var delays = delaysPtr.pointee
    for i in 0..<frameCount {
        let idx = i * stride
        var sample = samples[idx] * preamp

        for band in 0..<bandCount {
            let c = coeffs[band]
            var d = delays[band]
            let x = sample
            let y = c.b0 * x + c.b1 * d.x1 + c.b2 * d.x2 - c.a1 * d.y1 - c.a2 * d.y2
            d.x2 = d.x1
            d.x1 = x
            d.y2 = d.y1
            d.y1 = y
            delays[band] = d
            sample = y
        }

        // Soft limiter: tanh-like curve using a cheap polynomial approximation. Prevents the
        // preamp from driving the output past ±1.0 and causing speaker-damaging clipping.
        samples[idx] = softLimit(sample)
    }
    delaysPtr.pointee = delays
}

@inline(__always)
private func softLimit(_ x: Float) -> Float {
    // Linear pass-through below a soft knee at ±0.9; rational curve above to gently saturate at ±1.
    // Protects speakers when the preamp + EQ peaks drive samples past nominal range.
    let absX = x < 0 ? -x : x
    if absX < 0.9 { return x }
    let sign: Float = x < 0 ? -1 : 1
    let over = absX - 0.9
    let squeezed = 0.1 * over / (0.1 + over)  // asymptotes to 0.1 as `over` grows
    return sign * (0.9 + squeezed)
}
