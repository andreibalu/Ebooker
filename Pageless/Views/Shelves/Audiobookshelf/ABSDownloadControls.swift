import SwiftUI

struct ABSDownloadControls: View {
    let book: Audiobook
    var isOffline = false
    var client: AudiobookshelfClient = ABSAccount.shared.client
    @EnvironmentObject private var player: AudioPlayerManager
    @State private var manager = ABSDownloadManager.shared

    private var serverUnavailable: Bool { isOffline || !NetworkMonitor.shared.isConnected }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let job = manager.jobs[book.id] {
                if let error = job.error {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("abs.download.error")
                    Button("Retry Download") { Task { await manager.retry(book.id) } }
                        .disabled(serverUnavailable)
                        .accessibilityIdentifier("abs.download.retry")
                } else {
                    ProgressView(value: manager.progress(for: book.id)) {
                        Text("Downloading \(Int(manager.progress(for: book.id) * 100))%")
                    }
                    .accessibilityIdentifier("abs.download.progress")
                }
                Button("Cancel Download", role: .destructive) { Task { await manager.cancel(book.id) } }
                    .accessibilityIdentifier("abs.download.cancel")
            } else if book.isDownloaded {
                Button("Remove Download", role: .destructive) {
                    Task {
                        player.unloadIfCurrent(book)
                        await manager.removeDownload(book)
                    }
                }
                .accessibilityIdentifier("abs.download.remove")
                Text("Downloaded on this iPhone. Plays without your server.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Download") { Task { await manager.start(book, client: client) } }
                    .disabled(serverUnavailable)
                    .accessibilityIdentifier("abs.download.start")
                if serverUnavailable {
                    Text("Connect to your server to download or stream this book.")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("abs.download.offline")
                }
            }
            if !book.isDownloaded {
                Text("Download this book to use recaps and smart moments.")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("abs.ai.downloadRequired")
            }
            if let error = manager.storageError {
                Text(error).font(.footnote).foregroundStyle(.red)
                    .accessibilityIdentifier("abs.download.storageError")
            }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ABSDownloadsSection: View {
    @State private var manager = ABSDownloadManager.shared
    var body: some View {
        if !manager.jobs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Audiobookshelf Downloads").font(.subheadline.weight(.semibold))
                ForEach(manager.jobs.values.sorted { $0.title < $1.title }, id: \.bookID) { job in
                    if let book = manager.book(id: job.bookID) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(job.title).font(.subheadline)
                            ABSDownloadControls(book: book)
                        }
                        .padding(12)
                        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("abs.download.pinned.\(job.bookID)")
                    }
                }
            }
            .accessibilityIdentifier("abs.downloads")
        }
    }
}
