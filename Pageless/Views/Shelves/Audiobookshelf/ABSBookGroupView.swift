import SwiftUI

/// A series or collection screen; `groupID == nil` is the index of every group of `kind`.
struct ABSGroupRoute: Hashable {
    let libraryID: String
    let kind: String
    let title: String
    var groupID: String? = nil
}

/// Series, collections and people share the same editorial book rows and cached states.
struct ABSBookGroupView: View {
    let libraryID: String
    let kind: String
    let title: String
    var groupID: String? = nil
    var person: String? = nil
    let onOpenPlayer: () -> Void
    var account: ABSAccount = .shared
    @State private var viewModel = ABSBookGroupViewModel()

    private var isIndex: Bool { groupID == nil && person == nil }
    private var rowPrefix: String { kind == "series" ? "abs.series.row" : "abs.collection.row" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ABSEyebrow(text: "Audiobookshelf · \(kind)")
                Text(title).font(ABSType.display()).accessibilityAddTraits(.isHeader)
                if viewModel.isOffline && viewModel.phase == .loaded {
                    Text("Offline · Showing saved shelves.")
                        .font(.subheadline)
                        .accessibilityIdentifier("abs.group.offline")
                    retry
                }
                switch viewModel.phase {
                case .loading:
                    ProgressView("Loading shelf").accessibilityIdentifier("abs.group.loading")
                case .loaded:
                    if isIndex {
                        if viewModel.groups.isEmpty { emptyState }
                        ForEach(viewModel.groups) { group in
                            NavigationLink(value: ABSGroupRoute(libraryID: libraryID, kind: kind, title: group.name, groupID: group.id)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.name).font(ABSType.title())
                                        Text("\(group.books.count) books").font(ABSType.body()).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("\(rowPrefix).\(group.id)")
                            Divider()
                        }
                    } else {
                        if viewModel.books.isEmpty { emptyState }
                        ForEach(Array(viewModel.books.enumerated()), id: \.element.id) { index, book in
                            NavigationLink {
                                ABSBookDetailView(item: book, progress: nil, onOpenPlayer: onOpenPlayer, account: account)
                            } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    ABSCoverView(itemID: book.id, title: book.media.metadata.displayTitle, hasCover: book.media.hasCover, client: account.client)
                                        .frame(width: 54, height: 72).clipped()
                                    VStack(alignment: .leading, spacing: 5) {
                                        if kind == "series", let sequence = book.sequence, !sequence.trimmingCharacters(in: .whitespaces).isEmpty {
                                            ABSEyebrow(text: "Book \(sequence)")
                                        }
                                        Text(book.media.metadata.displayTitle).font(ABSType.title())
                                        Text(book.media.metadata.displayAuthor).font(ABSType.body()).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(index + 1), \(book.media.metadata.displayTitle), by \(book.media.metadata.displayAuthor)\(sequenceLabel(book))")
                            .accessibilityIdentifier("abs.group.book.\(book.id)")
                            Divider()
                        }
                    }
                default:
                    ABSStateView(eyebrow: "Shelf unavailable", title: "Couldn't load this shelf.",
                                 message: message, actionTitle: "Retry", actionIdentifier: "abs.group.retry",
                                 action: { Task { await load() } })
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .background(Color.cream.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .accessibilityIdentifier("abs.group")
    }

    private var emptyState: some View {
        Text("No books on this shelf yet.").font(.system(.subheadline, design: .serif))
            .foregroundStyle(.secondary).accessibilityIdentifier("abs.group.empty")
    }

    private var retry: some View {
        Button("Retry") { Task { await load() } }.accessibilityIdentifier("abs.group.retry")
    }

    private var message: String {
        switch viewModel.phase {
        case .signedOut: "Reconnect to your Audiobookshelf server to browse this shelf."
        case .failed(let message): message
        default: ABSConnectViewModel.unreachableMessage(host: account.summary?.host ?? "your server")
        }
    }

    private func sequenceLabel(_ book: ABSLibraryItem) -> String {
        guard kind == "series", let sequence = book.sequence, !sequence.isEmpty else { return "" }
        return ", Book \(sequence)"
    }

    private func load() async {
        await viewModel.load(libraryID: libraryID, kind: kind, groupID: groupID, person: person, account: account)
    }
}
