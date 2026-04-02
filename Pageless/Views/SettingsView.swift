//
//  SettingsView.swift
//  Pageless
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var aiEntitlement: AIEntitlementStore

    @AppStorage("resumeBacktrackSeconds") private var resumeBacktrackSeconds = ResumeBacktrackOption.oneMinute.rawValue
    @AppStorage("skipBackSeconds") private var skipBackSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("momentBacktrackSeconds") private var momentBacktrackSeconds = MomentBacktrackOption.exact.rawValue

    private var canPurchaseOnDevice: Bool {
        AppleIntelligenceCapability.canPurchaseAIUnlockOnThisDevice
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !canPurchaseOnDevice {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI Features")
                            Text("Requires an Apple Intelligence–compatible device.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        NavigationLink {
                            AISettingsView()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("AI Features")
                                    Text(aiTeaserSubline)
                                        .font(.caption)
                                        .foregroundStyle(aiTeaserSublineAccent ? Color.orange : Color.secondary)
                                }
                                Spacer()
                                if aiEntitlement.isUnlocked {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        SettingsDoubleOptionList(
                            navigationTitle: "On Resume",
                            selection: $resumeBacktrackSeconds,
                            options: Array(ResumeBacktrackOption.allCases),
                            rowTitle: \.title
                        )
                    } label: {
                        playbackSettingRow(
                            title: "On Resume",
                            caption: "Rewind a bit when you press play after a break",
                            valueTitle: ResumeBacktrackOption(rawValue: resumeBacktrackSeconds)?.title ?? ""
                        )
                    }
                }

                Section {
                    NavigationLink {
                        SettingsDoubleOptionList(
                            navigationTitle: "Save Moment Offset",
                            selection: $momentBacktrackSeconds,
                            options: Array(MomentBacktrackOption.allCases),
                            rowTitle: \.title
                        )
                    } label: {
                        playbackSettingRow(
                            title: "Save Moment Offset",
                            caption: "How far back the timestamp is set when you save a moment",
                            valueTitle: MomentBacktrackOption(rawValue: momentBacktrackSeconds)?.title ?? ""
                        )
                    }
                }

                Section {
                    NavigationLink {
                        SettingsDoubleOptionList(
                            navigationTitle: "Skip Backward",
                            selection: $skipBackSeconds,
                            options: Array(SkipIntervalOption.allCases),
                            rowTitle: \.title
                        )
                    } label: {
                        playbackSettingRow(
                            title: "Skip Backward",
                            caption: "How far the \u{21A9} button jumps back",
                            valueTitle: SkipIntervalOption(rawValue: skipBackSeconds)?.title ?? ""
                        )
                    }

                    NavigationLink {
                        SettingsDoubleOptionList(
                            navigationTitle: "Skip Forward",
                            selection: $skipForwardSeconds,
                            options: Array(SkipIntervalOption.allCases),
                            rowTitle: \.title
                        )
                    } label: {
                        playbackSettingRow(
                            title: "Skip Forward",
                            caption: "How far the \u{21AA} button jumps ahead",
                            valueTitle: SkipIntervalOption(rawValue: skipForwardSeconds)?.title ?? ""
                        )
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.cream.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.cream, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await aiEntitlement.loadProduct()
            }
            .alert(
                "Purchase",
                isPresented: Binding(
                    get: { aiEntitlement.purchaseError != nil },
                    set: { if !$0 { aiEntitlement.purchaseError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    aiEntitlement.purchaseError = nil
                }
            } message: {
                Text(aiEntitlement.purchaseError ?? "")
            }
            .alert(
                "Restore",
                isPresented: Binding(
                    get: { aiEntitlement.restoreError != nil },
                    set: { if !$0 { aiEntitlement.restoreError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    aiEntitlement.restoreError = nil
                }
            } message: {
                Text(aiEntitlement.restoreError ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var aiTeaserSubline: String {
        if aiEntitlement.isUnlocked {
            return "Unlocked"
        }
        let price = aiEntitlement.unlockPriceDisplay
        if aiEntitlement.trialUsesRemaining > 0 {
            return "\(aiEntitlement.trialUsesRemaining) free tries left · Unlock for \(price)"
        }
        return "Free tries used up · Unlock for \(price)"
    }

    private var aiTeaserSublineAccent: Bool {
        !aiEntitlement.isUnlocked && aiEntitlement.trialUsesRemaining == 0
    }

    private func playbackSettingRow(title: String, caption: String, valueTitle: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(valueTitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Cream-styled option list (replaces system navigationLink picker sheet)

private struct SettingsDoubleOptionList<Option: Identifiable & RawRepresentable>: View
    where Option.RawValue == Double {
    let navigationTitle: String
    @Binding var selection: Double
    let options: [Option]
    let rowTitle: KeyPath<Option, String>

    var body: some View {
        List {
            ForEach(options) { option in
                Button {
                    selection = option.rawValue
                } label: {
                    HStack {
                        Text(option[keyPath: rowTitle])
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection == option.rawValue {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .listRowBackground(Color.cardWhite)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.cream.ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.cream, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AIEntitlementStore())
}
