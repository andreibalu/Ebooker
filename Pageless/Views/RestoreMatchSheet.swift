//
//  RestoreMatchSheet.swift
//  Pageless
//

import SwiftUI

/// Shown when a freshly imported file fingerprint-matches an orphan Audiobook that came down via
/// iCloud sync. Gives the user the choice to restore all the synced metadata (progress, moments,
/// EQ, recap, favorites) onto the new files, or to add the file as a brand-new book.
struct RestoreMatchSheet: View {
    let candidate: RestoreMatchCandidate
    let onRestore: () -> Void
    let onAddAsNew: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var orphan: Audiobook { candidate.orphan }

    private var momentCountText: String {
        let count = orphan.moments.count
        return count == 1 ? "1 moment" : "\(count) moments"
    }

    private var lastPlayedText: String? {
        guard let date = orphan.lastPlayedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last played \(formatter.localizedString(for: date, relativeTo: .now))"
    }

    private var progressText: String? {
        guard orphan.progress > 0 else { return nil }
        return "\(Int(orphan.progress * 100))% through"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    coverArt
                        .padding(.top, 8)

                    Text("Looks like '\(orphan.title)'")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text("Restore your progress, moments, and settings from iCloud?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 6) {
                        if !orphan.author.isEmpty {
                            row(icon: "person.fill", text: orphan.displayAuthor)
                        }
                        row(icon: "bookmark.fill", text: momentCountText)
                        if let progress = progressText {
                            row(icon: "chart.bar.fill", text: progress)
                        }
                        if let last = lastPlayedText {
                            row(icon: "clock.fill", text: last)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    VStack(spacing: 10) {
                        Button {
                            onRestore()
                            dismiss()
                        } label: {
                            Text("Restore from iCloud")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            onAddAsNew()
                            dismiss()
                        } label: {
                            Text("Add as new book")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("iCloud match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var coverArt: some View {
        if let data = orphan.coverArtData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 6, y: 3)
        } else {
            GeneratedCoverView(title: orphan.title)
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 6, y: 3)
        }
    }

    private func row(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
        }
    }
}
