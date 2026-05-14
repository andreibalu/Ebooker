//
//  ComebackPromptSheet.swift
//  Pageless
//

import SwiftUI

/// Sheet shown when the user opens a book they haven't listened to in 4+ hours
/// and has the welcome-back recap feature enabled.
struct ComebackPromptSheet: View {
    let prompt: ComebackPromptCoordinator.PendingPrompt
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.primary)
                Text("Want a quick recap?")
                    .font(.title3.weight(.semibold))
                Spacer()
            }

            if prompt.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Building your recap…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            } else if let recap = prompt.recap {
                recapBody(recap)
            } else if let error = prompt.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button(role: .cancel) {
                    onNo()
                } label: {
                    Text("Skip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onYes()
                } label: {
                    Text(prompt.recap == nil ? "Just play" : "Start playing")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.isLoading)
            }
        }
        .padding(20)
        .background(Color.cream.ignoresSafeArea())
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func recapBody(_ recap: ComebackRecapResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let anchor = anchorLine(recap)
            if !anchor.isEmpty {
                Text(anchor)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            if !recap.summary.isEmpty {
                Text(recap.summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Builds the "You're in {location} with {characters}." anchor line, gracefully
    /// degrading when either field is empty.
    static func anchorLine(_ recap: ComebackRecapResult) -> String {
        let names = recap.characters.filter { !$0.isEmpty }
        let charText = formatCharacters(names)
        switch (recap.location.isEmpty, charText.isEmpty) {
        case (false, false): return "You're in \(recap.location) with \(charText)."
        case (false, true):  return "You're in \(recap.location)."
        case (true, false):  return "You're with \(charText)."
        case (true, true):   return ""
        }
    }

    private func anchorLine(_ recap: ComebackRecapResult) -> String {
        Self.anchorLine(recap)
    }

    private static func formatCharacters(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            let head = names.dropLast().joined(separator: ", ")
            return "\(head), and \(names.last!)"
        }
    }
}
