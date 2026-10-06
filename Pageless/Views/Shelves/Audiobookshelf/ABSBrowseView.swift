//
//  ABSBrowseView.swift
//  Pageless
//
//  Shelves tab content when the Audiobookshelf source is selected.
//

import SwiftUI

struct ABSBrowseView: View {
    let onOpenPlayer: () -> Void
    var account: ABSAccount = .shared

    @State private var viewModel = ABSBrowseViewModel()
    @State private var isReconnectPresented = false
    @AppStorage("absSelectedLibraryID") private var storedLibraryID = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3)

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 16)

                if viewModel.phase == .loaded && viewModel.hasContent {
                    searchBar(text: $vm.searchQuery)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }

                content
            }
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color.cream.ignoresSafeArea())
        .refreshable { await reload() }
        .task { await viewModel.loadIfNeeded(account: account, preferredLibraryID: storedLibraryID) }
        .sheet(isPresented: $isReconnectPresented) {
            ABSConnectView(account: account, initialServer: account.summary?.baseURL.absoluteString ?? "") {
                Task { await reload() }
            }
        }
        .onChange(of: account.summary) { _, _ in
            Task { await reload() }
        }
        .accessibilityIdentifier("abs.browse")
    }

    // MARK: - Header

    private var hostLabel: String { account.summary?.host ?? "Not connected" }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            ABSEyebrow(text: "Audiobookshelf · \(hostLabel)")
            if viewModel.libraries.count > 1 {
                Menu {
                    ForEach(viewModel.libraries, id: \.id) { library in
                        Button {
                            storedLibraryID = library.id
                            Task { await viewModel.selectLibrary(library.id, account: account) }
                        } label: {
                            if library.id == viewModel.selectedLibraryID {
                                Label(library.name, systemImage: "checkmark")
                            } else {
                                Text(library.name)
                            }
                        }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(viewModel.selectedLibrary?.name ?? "Library")
                            .font(ABSType.display())
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Library: \(viewModel.selectedLibrary?.name ?? "")")
                .accessibilityHint("Switch library")
                .accessibilityIdentifier("abs.browse.libraryMenu")
            } else {
                Text(viewModel.selectedLibrary?.name ?? "Your library")
                    .font(ABSType.display())
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            loadingSkeleton
        case .offline:
            stateContainer(ABSStateView(
                eyebrow: "Offline",
                title: "You're offline.",
                message: "Your server's shelves will be here when you're back online. Books already in your Library keep their place.",
                actionTitle: "Try Again", actionIdentifier: "abs.browse.retry",
                action: { Task { await reload() } }
            ))
        case .unreachable:
            stateContainer(ABSStateView(
                eyebrow: "Server unavailable",
                title: "Can't reach \(hostLabel).",
                message: "Check that your server is running and reachable from this iPhone. If you reach it over a VPN like Tailscale, make sure it's switched on.",
                actionTitle: "Retry", actionIdentifier: "abs.browse.retry",
                action: { Task { await reload() } }
            ))
        case .signedOut:
            stateContainer(ABSStateView(
                eyebrow: "Signed out",
                title: "Your sign-in has expired.",
                message: "Reconnect to \(hostLabel) to keep browsing your shelf.",
                actionTitle: "Reconnect", actionIdentifier: "abs.browse.reconnect",
                action: { isReconnectPresented = true }
            ))
        case .noBookLibraries:
            stateContainer(ABSStateView(
                eyebrow: "No book libraries",
                title: "Nothing to shelve yet.",
                message: "This server has no audiobook libraries. Podcast libraries aren't shown in Unpaged.",
                actionTitle: "Refresh", actionIdentifier: "abs.browse.retry",
                action: { Task { await reload() } }
            ))
        case .failed(let message):
            stateContainer(ABSStateView(
                eyebrow: "Something went wrong",
                title: "Couldn't load your shelf.",
                message: message,
                actionTitle: "Retry", actionIdentifier: "abs.browse.retry",
                action: { Task { await reload() } }
            ))
        case .loaded:
            if !viewModel.hasContent {
                stateContainer(ABSStateView(
                    eyebrow: "Empty library",
                    title: "This shelf is empty.",
                    message: "Add audiobooks to \(viewModel.selectedLibrary?.name ?? "this library") on your server, then refresh.",
                    actionTitle: "Refresh", actionIdentifier: "abs.browse.retry",
                    action: { Task { await reload() } }
                ))
            } else if viewModel.isSearching {
                searchResults
            } else {
                shelves
            }
        }
    }

    private func stateContainer(_ state: ABSStateView) -> some View {
        state
            .frame(minHeight: 420)
            .transition(.opacity)
    }

    @ViewBuilder
    private var shelves: some View {
        VStack(alignment: .leading, spacing: 30) {
            let continuing = viewModel.continueListening
            if !continuing.isEmpty {
                rail(title: "Continue Listening", items: continuing, showsProgress: true, identifier: "abs.browse.continue")
            }
            let recent = viewModel.recentlyAdded
            if !recent.isEmpty {
                rail(title: "Recently Added", items: recent, showsProgress: false, identifier: "abs.browse.recent")
            }

            VStack(alignment: .leading, spacing: 16) {
                ABSSectionHeader(title: "All Books")
                    .padding(.horizontal, 20)
                grid(viewModel.allBooks)
                    .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = viewModel.searchResults
        VStack(alignment: .leading, spacing: 16) {
            ABSEyebrow(text: results.count == 1 ? "1 result" : "\(results.count) results")
                .padding(.horizontal, 20)
            if results.isEmpty {
                Text("No titles or authors match “\(viewModel.searchQuery)”.")
                    .font(.system(.subheadline, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                grid(results).padding(.horizontal, 20)
            }
        }
    }

    private func rail(title: String, items: [ABSLibraryItem], showsProgress: Bool, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ABSSectionHeader(title: title)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
                        link(for: item) {
                            ABSBookTile(
                                item: item,
                                progress: showsProgress ? viewModel.progress(for: item)?.progress : nil
                            )
                            .frame(width: 128)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private func grid(_ items: [ABSLibraryItem]) -> some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 22) {
            ForEach(items) { item in
                link(for: item) {
                    ABSBookTile(item: item, progress: nil)
                }
            }
        }
        .accessibilityIdentifier("abs.browse.grid")
    }

    private func link<Label: View>(for item: ABSLibraryItem, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink {
            ABSBookDetailView(item: item, progress: viewModel.progress(for: item), onOpenPlayer: onOpenPlayer, account: account)
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("abs.book.\(item.id)")
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            ABSSectionHeader(title: "Recently Added")
                .redacted(reason: .placeholder)
            LazyVGrid(columns: gridColumns, spacing: 22) {
                ForEach(0..<9, id: \.self) { _ in ABSSkeletonCover() }
            }
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your library")
    }

    // MARK: - Search

    private func searchBar(text: Binding<String>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                "",
                text: text,
                prompt: Text("Search titles & authors…")
                    .font(.system(.subheadline, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
            )
            .font(.system(.subheadline, design: .serif))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .accessibilityLabel("Search this library")
            .accessibilityIdentifier("abs.browse.search")
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.cardWhite, in: Capsule())
        .overlay(Capsule().strokeBorder(ABSType.hairline, lineWidth: 0.5))
    }

    private func reload() async {
        await viewModel.load(account: account, preferredLibraryID: storedLibraryID.isEmpty ? nil : storedLibraryID)
    }
}

/// Cover + serif title + secondary author (two lines max between them).
struct ABSBookTile: View {
    let item: ABSLibraryItem
    let progress: Double?

    var body: some View {
        let metadata = item.media.metadata
        VStack(alignment: .leading, spacing: 7) {
            ABSCoverView(itemID: item.id, title: metadata.displayTitle, hasCover: item.media.hasCover)
            if let progress {
                ABSProgressBar(fraction: progress)
                    .padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(metadata.displayTitle)
                    .font(ABSType.title())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(metadata.displayAuthor)
                    .font(ABSType.body())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var parts = [item.media.metadata.displayTitle, "by \(item.media.metadata.displayAuthor)"]
        if let progress { parts.append("\(TimeFormatter.percentValue(progress)) percent listened") }
        return parts.joined(separator: ", ")
    }
}
