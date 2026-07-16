//
//  LibriVoxDownloadSection.swift
//  Pageless
//

import SwiftUI

@MainActor
struct LibriVoxDownloadPresentation {
    let entry: LibriVoxDownloadManager.Entry

    var statusText: String {
        switch entry.phase {
        case .preparing: "Preparing…"
        case .downloading: "\(entry.completedTracks) of \(entry.totalTracks) tracks"
        case .cancelling: "Cancelling…"
        case .failed: entry.errorMessage ?? "Download failed"
        case .complete: "Downloaded"
        }
    }

    var progress: Double? {
        guard entry.phase == .downloading, entry.totalTracks > 0 else { return nil }
        return entry.progress
    }

    var showsSpinner: Bool { entry.phase == .preparing || entry.phase == .cancelling }
    var canCancel: Bool { entry.phase == .preparing || entry.phase == .downloading }
    var canRetry: Bool { entry.phase == .failed }
    var canDismiss: Bool { entry.phase == .failed }

    static func cardStatus(
        entry: LibriVoxDownloadManager.Entry?,
        isStreamingOnly: Bool
    ) -> String? {
        guard let entry else { return isStreamingOnly ? "Stream" : nil }
        switch entry.phase {
        case .preparing: return "Preparing"
        case .downloading: return "Downloading \(entry.completedTracks) of \(entry.totalTracks)"
        case .cancelling: return "Cancelling"
        case .failed: return "Download Failed"
        case .complete: return "Downloaded"
        }
    }
}

@MainActor
struct LibriVoxDownloadAnimationKey: Equatable {
    struct Item: Equatable {
        let catalogID: String
        let phase: LibriVoxDownloadManager.Phase
    }

    let items: [Item]

    init(entries: [LibriVoxDownloadManager.Entry]) {
        items = entries.map {
            Item(catalogID: $0.catalogID, phase: $0.phase)
        }
    }
}

/// Shared, compact download surface used by Free Books and the Library tab.
struct LibriVoxDownloadSection: View {
    @Environment(LibriVoxDownloadManager.self) private var manager
    var onSelect: ((String) -> Void)? = nil

    private var entries: [LibriVoxDownloadManager.Entry] {
        manager.entries.values.sorted { $0.metadata.title < $1.metadata.title }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .id("library-downloads")

            if !entries.isEmpty {
                HStack(spacing: 10) {
                    Text("Downloads · \(entries.count)")
                        .font(.subheadline.weight(.semibold))
                    Rectangle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(height: 0.5)
                }

                ForEach(entries, id: \.catalogID) { entry in
                    row(entry)
                    if entry.catalogID != entries.last?.catalogID {
                        Divider()
                    }
                }
            }
        }
    }

    private func row(_ entry: LibriVoxDownloadManager.Entry) -> some View {
        let presentation = LibriVoxDownloadPresentation(entry: entry)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Group {
                    if let onSelect {
                        Button {
                            onSelect(entry.catalogID)
                        } label: {
                            rowSummary(entry, presentation: presentation)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens book details")
                    } else {
                        rowSummary(entry, presentation: presentation)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                if presentation.showsSpinner {
                    ProgressView().controlSize(.small)
                }
                actions(for: entry, presentation: presentation)
            }

            if let progress = presentation.progress {
                ProgressView(value: progress)
                    .tint(.amber)
            }
        }
        .padding(.vertical, 10)
    }

    private func rowSummary(
        _ entry: LibriVoxDownloadManager.Entry,
        presentation: LibriVoxDownloadPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.metadata.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(presentation.statusText)
                .font(.caption)
                .foregroundStyle(entry.phase == .failed ? Color.red : Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func actions(
        for entry: LibriVoxDownloadManager.Entry,
        presentation: LibriVoxDownloadPresentation
    ) -> some View {
        if presentation.canCancel {
            Button {
                Task { await manager.cancel(catalogID: entry.catalogID) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel download")
        } else if presentation.canRetry || presentation.canDismiss {
            HStack(spacing: 10) {
                Button("Retry") { manager.retry(catalogID: entry.catalogID) }
                Button("Dismiss") { manager.dismiss(catalogID: entry.catalogID) }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
        }
    }
}

/// Shared five-phase status/actions used by both LibriVox detail routes.
struct LibriVoxDetailDownloadStatus: View {
    @Environment(LibriVoxDownloadManager.self) private var manager
    let entry: LibriVoxDownloadManager.Entry
    var progressTint: Color = .amber

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch entry.phase {
            case .preparing:
                Label("Preparing download…", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            case .downloading:
                HStack {
                    Text("Downloading…").fontWeight(.medium)
                    Spacer()
                    Text("\(entry.completedTracks) / \(entry.totalTracks) tracks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(
                    value: entry.progress
                )
                .tint(progressTint)
            case .cancelling:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Cancelling…").foregroundStyle(.secondary)
                }
            case .failed:
                Label(entry.errorMessage ?? "The download failed.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                HStack {
                    Button("Try Again") { manager.retry(catalogID: entry.catalogID) }
                    Button("Dismiss") { manager.dismiss(catalogID: entry.catalogID) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .complete:
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }

            if entry.phase == .preparing || entry.phase == .downloading {
                Button("Cancel") {
                    Task { await manager.cancel(catalogID: entry.catalogID) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}
