//
//  SettingsView.swift
//  Ebooker
//

import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var aiEntitlement: AIEntitlementStore

    @AppStorage("resumeBacktrackSeconds") private var resumeBacktrackSeconds = ResumeBacktrackOption.oneMinute.rawValue
    @AppStorage("skipBackSeconds") private var skipBackSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("momentBacktrackSeconds") private var momentBacktrackSeconds = MomentBacktrackOption.exact.rawValue
    @AppStorage("useLocalAIFeatures") private var useLocalAIFeatures = false
    @AppStorage("useSmartMomentNaming") private var useSmartMomentNaming = false
    @AppStorage("useSmartSummary") private var useSmartSummary = false
    @AppStorage("shortenSummary") private var shortenSummary = false

    private var isSmartNamingAvailable: Bool {
        AppleIntelligenceCapability.isSmartNamingAvailable
    }

    private var canPurchaseOnDevice: Bool {
        AppleIntelligenceCapability.canPurchaseAIUnlockOnThisDevice
    }

    /// AI toggles need an active purchase and a device/runtime where Apple Intelligence can run.
    private var aiTogglesDisabled: Bool {
        !aiEntitlement.isUnlocked || !isSmartNamingAvailable
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    aiPurchaseBlock

                    Toggle(isOn: $useLocalAIFeatures) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Use local AI features")
                                .font(.body)
                            Text("Enable Apple Intelligence features for this app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(aiTogglesDisabled)

                    if useLocalAIFeatures {
                        Toggle(isOn: $useSmartMomentNaming) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Smart moment naming")
                                    .font(.body)
                                Text("Suggest names for saved moments based on the audio")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(aiTogglesDisabled)

                        Toggle(isOn: $useSmartSummary) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Smart summary")
                                    .font(.body)
                                Text("Summarize where you left off on the book detail screen")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(aiTogglesDisabled)

                        if useSmartSummary {
                            Toggle(isOn: $shortenSummary) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Short progress headline")
                                        .font(.body)
                                    Text("Replace “Your progress” with a 3–4 word summary on one line")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .disabled(aiTogglesDisabled)
                        }
                    }

                    if !aiEntitlement.isUnlocked {
                        Text("Purchase the AI unlock to enable these options on a compatible device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !isSmartNamingAvailable, let reason = AppleIntelligenceCapability.unavailabilityReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("AI Features")
                } footer: {
                    Group {
                        if aiEntitlement.isUnlocked, isSmartNamingAvailable {
                            Text("Requires Apple Intelligence and a compatible device. Suggested moment names can be edited before saving.")
                        } else if !aiEntitlement.isUnlocked {
                            Text("Unlock once per Apple ID. Restore purchases if you reinstall or use a new device.")
                        }
                    }
                }
                .onChange(of: useLocalAIFeatures) { _, enabled in
                    if !enabled {
                        useSmartMomentNaming = false
                        useSmartSummary = false
                        shortenSummary = false
                    }
                }
                .onChange(of: useSmartSummary) { _, enabled in
                    if !enabled {
                        shortenSummary = false
                    }
                }

                Section {
                    Picker(selection: $resumeBacktrackSeconds) {
                        ForEach(ResumeBacktrackOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("On Resume")
                                .font(.body)
                            Text("Rewind a bit when you press play after a break")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    Picker(selection: $momentBacktrackSeconds) {
                        ForEach(MomentBacktrackOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Save Moment Offset")
                                .font(.body)
                            Text("How far back the timestamp is set when you save a moment")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    Picker(selection: $skipBackSeconds) {
                        ForEach(SkipIntervalOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Skip Backward")
                                .font(.body)
                            Text("How far the \u{21A9} button jumps back")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .pickerStyle(.navigationLink)

                    Picker(selection: $skipForwardSeconds) {
                        ForEach(SkipIntervalOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Skip Forward")
                                .font(.body)
                            Text("How far the \u{21AA} button jumps ahead")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .navigationTitle("Playback Settings")
            .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private var aiPurchaseBlock: some View {
        if aiEntitlement.isUnlocked {
            Label("AI features unlocked", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            restorePurchasesButton
        } else if canPurchaseOnDevice {
            Text("Unlock smart moment naming and progress summaries powered by on-device Apple Intelligence.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if aiEntitlement.isLoadingProduct {
                ProgressView()
                    .padding(.vertical, 4)
            }

            if let loadError = aiEntitlement.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await aiEntitlement.purchase() }
            } label: {
                if let product = aiEntitlement.product {
                    Text("Unlock — \(product.displayPrice)")
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Unlock")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(aiEntitlement.product == nil || aiEntitlement.isPurchasing || aiEntitlement.isLoadingProduct)

            restorePurchasesButton
        } else {
            Text(
                "On-device AI requires iOS 18 or later and a compatible device (for example iPhone 15 Pro or newer, or an iPad with an M-series chip). You can’t buy the AI unlock on this device."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("If you already purchased on another device, use Restore purchases.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            restorePurchasesButton
        }
    }

    private var restorePurchasesButton: some View {
        Button("Restore purchases") {
            Task { await aiEntitlement.restorePurchases() }
        }
        .font(.subheadline)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AIEntitlementStore())
}
