//
//  LyricsView.swift
//  Ebooker
//

import SwiftUI

struct LyricsView: View {
    let status: LyricsStatus
    let segments: [LyricsSegment]
    let currentTime: Double
    let onRetry: () -> Void

    private var activeSegmentID: Int? {
        segments.last(where: { $0.start <= currentTime })?.id
    }

    var body: some View {
        switch status {
        case .modelNotReady:
            modelNotReadyView
        case .transcribing(let progress):
            transcribingView(progress: progress)
        case .ready:
            lyricsScrollView
        case .failed(let message):
            failedView(message: message)
        }
    }

    // MARK: - States

    private var modelNotReadyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Lyrics Unavailable")
                .font(.headline)
            Text("Download the WhisperKit model in Settings to generate synced lyrics.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transcribingView(progress: Double) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .tint(Color.primary.opacity(0.7))
                .padding(.horizontal, 8)
            Text("Generating lyrics… \(Int(progress * 100))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("You can keep listening while this runs.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lyricsScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(segments) { segment in
                        let isActive = segment.id == activeSegmentID
                        Text(segment.text)
                            .font(.title3.weight(isActive ? .bold : .regular))
                            .foregroundStyle(
                                isActive
                                    ? AnyShapeStyle(Color.primary)
                                    : AnyShapeStyle(Color.secondary.opacity(0.4))
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(segment.id)
                            .animation(.easeInOut(duration: 0.2), value: isActive)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .onChange(of: activeSegmentID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Transcription Failed")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                onRetry()
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
