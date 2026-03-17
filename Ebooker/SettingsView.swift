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

    var body: some View {
        NavigationStack {
            Form {
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
