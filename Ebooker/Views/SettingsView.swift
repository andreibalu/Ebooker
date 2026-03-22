//
//  SettingsView.swift
//  Ebooker
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

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

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                    .disabled(!isSmartNamingAvailable)

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
                        .disabled(!isSmartNamingAvailable)

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
                        .disabled(!isSmartNamingAvailable)

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
                            .disabled(!isSmartNamingAvailable)
                        }
                    }

                    if !isSmartNamingAvailable, let reason = AppleIntelligenceCapability.unavailabilityReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("AI Features")
                } footer: {
                    if isSmartNamingAvailable {
                        Text("Requires Apple Intelligence and a compatible device. Suggested moment names can be edited before saving.")
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
        }
        .presentationDetents([.medium, .large])
    }
}
