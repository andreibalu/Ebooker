//
//  ABSBookDetailView.swift
//  Pageless
//
//  One book on the user's Audiobookshelf server. "Play" adds it as a streaming book (no files
//  written, token-less URLs stored) and starts playback.
//

import SwiftData
import SwiftUI

struct ABSBookDetailView: View {
    let onOpenPlayer: () -> Void
    var account: ABSAccount

    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: ABSBookDetailViewModel
    @State private var isDescriptionExpanded = false

    init(item: ABSLibraryItem, progress: ABSMediaProgress?, onOpenPlayer: @escaping () -> Void, account: ABSAccount? = nil) {
        self.onOpenPlayer = onOpenPlayer
        self.account = account ?? .shared
        _viewModel = State(initialValue: ABSBookDetailViewModel(item: item, progress: progress))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ABSCoverView(
                    itemID: viewModel.summary.id,
                    title: viewModel.metadata.displayTitle,
                    hasCover: viewModel.media.hasCover,
                    cornerRadius: 12,
                    client: account.client
                )
                .frame(maxWidth: 230)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
                .padding(.top, 20)
                .padding(.bottom, 26)

                titleBlock
                    .padding(.bottom, 22)

                actions
                    .padding(.bottom, 26)

                if let description = cleanedDescription {
                    descriptionBlock(description)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 120)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color.cream.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(account: account, modelContext: modelContext) }
        .onAppear { viewModel.refreshLibraryBook(modelContext: modelContext) }
        .accessibilityIdentifier("abs.detail")
    }

    // MARK: - Title

    private var titleBlock: some View {
        let metadata = viewModel.metadata
        return VStack(spacing: 8) {
            eyebrow
                .multilineTextAlignment(.center)
            Text(metadata.displayTitle)
                .font(ABSType.display())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("abs.detail.title")
            if let subtitle = metadata.subtitle?.trimmingCharacters(in: .whitespaces), !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(.subheadline, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(metadata.displayAuthor)
                .font(.system(.body, design: .serif))
                .foregroundStyle(.primary)
            if let narrator = metadata.displayNarrator {
                Text("Read by \(narrator)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            statusLine
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    /// Duration stays lowercase ("11 hr 32 min") so it never reads as "11H" or "40S"; the word
    /// part is uppercased to match the eyebrow voice.
    private var eyebrowText: String {
        Self.eyebrowText(durationSeconds: viewModel.durationSeconds, chapterCount: viewModel.media.chapterCount)
    }

    /// One line of metadata, but lowercase duration letters get tighter tracking than the
    /// small-caps word part — wide-tracked lowercase reads as spaced-out, not as an eyebrow.
    private var eyebrow: some View {
        let duration = viewModel.durationSeconds > 0 ? Self.durationText(viewModel.durationSeconds) : ""
        let rest = String(eyebrowText.dropFirst(duration.count))
        return Text("\(Text(duration).tracking(0.4))\(Text(rest).tracking(1.2))")
            .font(ABSType.eyebrow())
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .accessibilityLabel(eyebrowText.lowercased())
    }

    static func eyebrowText(durationSeconds: Double, chapterCount: Int) -> String {
        var parts: [String] = []
        if durationSeconds > 0 { parts.append(durationText(durationSeconds)) }
        if chapterCount > 0 {
            parts.append((chapterCount == 1 ? "1 chapter" : "\(chapterCount) chapters").uppercased())
        }
        return parts.isEmpty ? "AUDIOBOOKSHELF" : parts.joined(separator: " · ")
    }

    /// "11 hr 32 min", "2 hr", "45 min", "under 1 min".
    static func durationText(_ seconds: Double) -> String {
        guard seconds >= 60 else { return "under 1 min" }
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes) min"
        case (_, 0): return "\(hours) hr"
        default: return "\(hours) hr \(minutes) min"
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        let inLibrary = viewModel.libraryBook != nil
        if inLibrary || viewModel.listenedText != nil {
            HStack(spacing: 8) {
                if inLibrary {
                    Label("In your Library", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .accessibilityIdentifier("abs.detail.inLibrary")
                }
                if let listened = viewModel.listenedText {
                    if inLibrary { Text("·") }
                    Text(listened)
                        .monospacedDigit()
                        .accessibilityIdentifier("abs.detail.listened")
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("abs.detail.status")
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await play() }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.actionState == .working {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "play.fill").accessibilityHidden(true)
                    }
                    Text(viewModel.primaryActionTitle)
                }
            }
            .buttonStyle(ABSPrimaryButtonStyle())
            .disabled(viewModel.actionState == .working)
            .accessibilityIdentifier("abs.detail.play")

            if viewModel.libraryBook == nil {
                Button {
                    Task { _ = await viewModel.addToLibrary(account: account, modelContext: modelContext) }
                } label: {
                    Text("Add to Library")
                }
                .buttonStyle(ABSSecondaryButtonStyle())
                .disabled(viewModel.actionState == .working)
                .accessibilityIdentifier("abs.detail.add")
            }

            if let error = viewModel.actionError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("abs.detail.error")
            }

            Text("Streams from your server — nothing is downloaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 400)
    }

    private func play() async {
        guard let book = await viewModel.addToLibrary(account: account, modelContext: modelContext) else { return }
        onOpenPlayer()
        await player.startPlayback(for: book)
    }

    // MARK: - Description

    private var cleanedDescription: String? {
        guard let raw = viewModel.metadata.description else { return nil }
        let text = BookDescriptionFormatting.plainText(fromHTMLFragment: raw)
        return text.isEmpty ? nil : text
    }

    private func descriptionBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ABSSectionHeader(title: "About this book")
            Text(text)
                .font(.system(.body, design: .serif))
                .lineSpacing(3)
                .lineLimit(isDescriptionExpanded ? nil : 5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if text.count > 280 {
                Button(isDescriptionExpanded ? "Show less" : "Show more") {
                    withAnimation(reduceMotion ? nil : AppMotion.stateChange) {
                        isDescriptionExpanded.toggle()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityIdentifier("abs.detail.descriptionToggle")
            }
        }
    }
}
