//
//  LibriVoxCollectionView.swift
//  Pageless
//

import SwiftUI

struct LibriVoxCollectionView: View {
    let collection: LibriVoxCollection
    let onOpenPlayer: () -> Void
    let browseViewModel: BrowseLibriVoxViewModel

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = LibriVoxCollectionViewModel()

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let isOffline):
                failedState(isOffline: isOffline)
            case .loaded:
                booksList
            }
        }
        .background(Color.cream.ignoresSafeArea())
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.load(collection: collection, modelContext: modelContext)
        }
    }

    private var booksList: some View {
        List {
            Section {
                ForEach(viewModel.books) { book in
                    NavigationLink {
                        LibriVoxBookDetailView(book: book, onOpenPlayer: onOpenPlayer, browseViewModel: browseViewModel)
                    } label: {
                        LibriVoxBookRow(book: book, browseViewModel: browseViewModel)
                    }
                    .listRowBackground(Color.cardWhite)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                }
            } header: {
                Text(collection.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }

            Text("Free books courtesy of [LibriVox](https://librivox.org) \u{2014} public domain audio recorded by volunteers.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .multilineTextAlignment(.center)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    private func failedState(isOffline: Bool) -> some View {
        ContentUnavailableView {
            Label(isOffline ? "No Internet Connection" : "Couldn’t Load Collection",
                  systemImage: isOffline ? "wifi.slash" : "exclamationmark.icloud")
        } description: {
            Text(isOffline
                 ? "This collection needs a connection the first time to load its books from LibriVox."
                 : "Something went wrong reaching LibriVox. Please try again in a moment.")
        } actions: {
            Button("Retry") {
                Task { await viewModel.retry(collection: collection, modelContext: modelContext) }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
