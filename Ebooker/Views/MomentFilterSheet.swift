//
//  MomentFilterSheet.swift
//  Ebooker
//

import SwiftUI

struct MomentFilterSheet: View {
    let audiobook: Audiobook
    @Bindable var viewModel: AudiobookDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let availableCategories = Set(audiobook.moments.flatMap(\.categories))
                if !availableCategories.isEmpty {
                    Section("Categories") {
                        ForEach(availableCategories.sorted(by: { $0.rawValue < $1.rawValue })) { category in
                            Button {
                                if viewModel.filterCategories.contains(category) {
                                    viewModel.filterCategories.remove(category)
                                } else {
                                    viewModel.filterCategories.insert(category)
                                }
                            } label: {
                                HStack {
                                    Text(category.displayName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if viewModel.filterCategories.contains(category) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                let availableCharacters = audiobook.castList
                if !availableCharacters.isEmpty {
                    Section("Characters") {
                        ForEach(availableCharacters, id: \.self) { character in
                            let key = character.lowercased()
                            Button {
                                if viewModel.filterCharacters.contains(key) {
                                    viewModel.filterCharacters.remove(key)
                                } else {
                                    viewModel.filterCharacters.insert(key)
                                }
                            } label: {
                                HStack {
                                    Text(character)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if viewModel.filterCharacters.contains(key) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                let availableMoods = Set(audiobook.moments.compactMap(\.mood))
                if !availableMoods.isEmpty {
                    Section("Moods") {
                        ForEach(availableMoods.sorted(by: { $0.rawValue < $1.rawValue })) { mood in
                            Button {
                                if viewModel.filterMoods.contains(mood) {
                                    viewModel.filterMoods.remove(mood)
                                } else {
                                    viewModel.filterMoods.insert(mood)
                                }
                            } label: {
                                HStack {
                                    Text(mood.displayName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if viewModel.filterMoods.contains(mood) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                if viewModel.hasActiveFilters {
                    Section {
                        Button("Clear All", role: .destructive) {
                            viewModel.clearFilters()
                        }
                    }
                }
            }
            .navigationTitle("Filter Moments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
