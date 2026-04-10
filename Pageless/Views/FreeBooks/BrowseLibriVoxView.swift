//
//  BrowseLibriVoxView.swift
//  Pageless
//

import SwiftUI

struct BrowseLibriVoxView: View {
    let onOpenPlayer: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = BrowseLibriVoxViewModel()

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)

            syncBanner
                .padding(.horizontal, 20)

            Divider()
                .padding(.horizontal, 20)

            contentArea
        }
        .background(Color.cream.ignoresSafeArea())
        .onAppear {
            viewModel.triggerSyncIfNeeded(modelContext: modelContext)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            TextField("Search 20,000+ free audiobooks", text: $viewModel.searchQuery)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: viewModel.searchQuery) { _, new in
                    viewModel.onQueryChanged(new, modelContext: modelContext)
                }

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                    viewModel.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - Sync banner

    @ViewBuilder
    private var syncBanner: some View {
        switch viewModel.syncState {
        case .syncing(let fetched):
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.75)
                Text("Syncing catalog… \(fetched.formatted()) books loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 6)

        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Retry") {
                    viewModel.forceRefresh(modelContext: modelContext)
                }
                .font(.caption.weight(.medium))
            }
            .padding(.vertical, 6)

        case .done, .idle:
            if LibriVoxCatalogSync.syncedBookCount > 0 {
                HStack {
                    Text(viewModel.lastSyncDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        viewModel.forceRefresh(modelContext: modelContext)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptySearch
        } else if viewModel.searchResults.isEmpty {
            noResults
        } else {
            resultsList
        }
    }

    private var emptySearch: some View {
        ContentUnavailableView {
            Label("Search LibriVox", systemImage: "magnifyingglass")
        } description: {
            Text("Find any of \(LibriVoxCatalogSync.syncedBookCount > 0 ? LibriVoxCatalogSync.syncedBookCount.formatted() + "+" : "thousands of") public-domain audiobooks by title or author.")
        }
    }

    private var noResults: some View {
        ContentUnavailableView.search(text: viewModel.searchQuery)
    }

    private var resultsList: some View {
        List {
            ForEach(viewModel.searchResults) { book in
                NavigationLink {
                    LibriVoxBookDetailView(book: book, onOpenPlayer: onOpenPlayer)
                } label: {
                    LibriVoxBookRow(book: book)
                }
                .listRowBackground(Color.cardWhite)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            viewModel.forceRefresh(modelContext: modelContext)
        }
    }
}
