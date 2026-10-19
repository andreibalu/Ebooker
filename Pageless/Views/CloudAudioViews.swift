//
//  CloudAudioViews.swift
//  Pageless
//

import SwiftUI

/// Shared copy for a book's audio in iCloud, so Cloud Library, the detail screen and the delete
/// dialogs describe the same state the same way.
enum CloudAudioCopy {
    /// Short status for a Cloud Library row; nil when nothing is in iCloud.
    static func rowStatus(_ state: CloudAudioState) -> String? {
        switch state {
        case .none: nil
        case .uploading(let fraction): "Uploading audio · \(TimeFormatter.percentValue(fraction))%"
        case .stored: "Audio in iCloud"
        case .partial: "Audio partly in iCloud"
        case .quotaExceeded: "iCloud storage is full"
        case .failed: "Audio upload paused"
        }
    }

    static func removeMessage(for book: Audiobook?) -> String {
        guard let book else { return "" }
        if book.isCloudOnlyOrphan {
            return "This iPhone doesn’t have the audio of ‘\(book.title)’. Once it’s gone from iCloud, you’ll need the original file to listen again, unless another device has it downloaded."
        }
        return "Deletes the audio of ‘\(book.title)’ from iCloud on all your devices. This iPhone keeps its copy, and the book stays in your library."
    }
}

/// Detail-screen card for an own book downloaded on this device: where its audio is, and the
/// per-book choice to store it in iCloud or remove it from there.
struct CloudAudioBookCard: View {
    let audiobook: Audiobook

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var store = CloudAudioStore.shared
    @State private var confirmRemove = false

    var body: some View {
        let state = store.state(for: audiobook)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol(for: state))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(state == .quotaExceeded ? Color.orange : Color.amber)
                    // The glyph sits in a fixed frame; past xxxLarge it would spill out of it.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    // One line beside the button; the stacked accessibility layout lets it wrap.
                    Text("Audio in iCloud")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    Text(caption(for: state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("book.cloudAudio.status")
                }
            }
            .layoutPriority(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            action(for: state)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        .confirmationDialog("Remove audio from iCloud?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Audio from iCloud", role: .destructive) {
                store.removeCloudAudio(folderName: audiobook.folderName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(CloudAudioCopy.removeMessage(for: audiobook))
        }
    }

    @ViewBuilder
    private func action(for state: CloudAudioState) -> some View {
        switch state {
        case .none, .partial:
            Button("Store") { store.store(audiobook) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel("Store audio in iCloud")
                .accessibilityIdentifier("book.cloudAudio.store")
        case .uploading:
            ProgressView()
                .accessibilityLabel("Uploading audio")
        case .stored, .quotaExceeded, .failed:
            Button("Remove", role: .destructive) { confirmRemove = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel("Remove audio from iCloud")
                .accessibilityIdentifier("book.cloudAudio.remove")
        }
    }

    private func symbol(for state: CloudAudioState) -> String {
        switch state {
        case .none: "icloud"
        case .uploading: "icloud.and.arrow.up"
        case .stored: "checkmark.icloud"
        case .partial, .failed: "exclamationmark.icloud"
        case .quotaExceeded: "xmark.icloud"
        }
    }

    private func caption(for state: CloudAudioState) -> String {
        switch state {
        case .none:
            "Only on this iPhone. Store it so your other devices can download it."
        case .uploading(let fraction):
            "Uploading · \(TimeFormatter.percentValue(fraction))%"
        case .stored:
            "Stored in iCloud. Your other devices can download it."
        case .partial:
            "Some of its files are in iCloud. Store it again to finish."
        case .quotaExceeded:
            "iCloud storage is full. Free up space in iCloud to finish uploading."
        case .failed:
            "Upload paused. iCloud retries on its own."
        }
    }
}
