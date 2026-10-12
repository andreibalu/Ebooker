import Foundation
import SwiftData
import UIKit
import WidgetKit

@MainActor
final class ContinueListeningSnapshotWriter {
    static let shared = ContinueListeningSnapshotWriter()
    static let groupID = "group.andreibaludev.Pageless"
    static let widgetKind = "ContinueListening"
    private var lastWrite = Date.distantPast
    private var lastBookID: UUID?
    private var coverTitle: String?
    private var coverData: Data?
    private var lastReload = Date.distantPast
    private var pendingReload: Task<Void, Never>?
    private var pendingRefresh: Task<Void, Never>?

    func write(_ book: Audiobook?, force: Bool = false) {
        guard force || book?.id != lastBookID || Date.now.timeIntervalSince(lastWrite) >= 30 else { return }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupID) else { return }
        do {
            let snapshotURL = container.appendingPathComponent("continue-listening.json")
            if let book {
                let coverURL = container.appendingPathComponent("\(book.id.uuidString).jpg")
                if lastBookID != book.id || coverTitle != book.title || coverData != book.coverArtData
                    || !FileManager.default.fileExists(atPath: coverURL.path) {
                    if let image = book.coverArtData.flatMap({ UIImage(data: $0) })
                        ?? GeneratedCoverView.renderImage(title: book.title, side: 300) {
                        let longest = max(image.size.width, image.size.height, 1)
                        let size = CGSize(width: image.size.width * 300 / longest, height: image.size.height * 300 / longest)
                        let format = UIGraphicsImageRendererFormat()
                        format.scale = 1
                        format.opaque = true
                        let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                            image.draw(in: CGRect(origin: .zero, size: size))
                        }
                        if let jpeg = thumbnail.jpegData(compressionQuality: 0.8) {
                            try jpeg.write(to: coverURL, options: .atomic)
                            coverTitle = book.title
                            coverData = book.coverArtData
                        }
                    }
                }
                let snapshot = Snapshot(bookID: book.id, title: book.title, author: book.author,
                                        progress: book.progress, timeLeft: max(0, book.totalDuration - book.listenedDuration),
                                        lastPlayedAt: book.lastPlayedAt ?? .now)
                try JSONEncoder().encode(snapshot).write(to: snapshotURL, options: .atomic)
            } else {
                try Data("null".utf8).write(to: snapshotURL, options: .atomic)
            }
            // Keep only the artwork referenced by the current snapshot.
            for file in try FileManager.default.contentsOfDirectory(at: container, includingPropertiesForKeys: nil)
                where file.pathExtension == "jpg" && file.lastPathComponent != book.map({ "\($0.id.uuidString).jpg" }) {
                try? FileManager.default.removeItem(at: file)
            }
            lastBookID = book?.id
            lastWrite = .now
            reload()
        } catch {
            // Widget state is best-effort; playback persistence remains independent.
        }
    }

    /// Coalesced and deferred: library mutations call this mid-transaction, often while a context
    /// menu is still dismissing, and rendering the next book's cover there is not safe.
    func refresh(context: ModelContext) {
        pendingRefresh?.cancel()
        pendingRefresh = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            pendingRefresh = nil
            let descriptor = FetchDescriptor<Audiobook>(sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)])
            guard let books = try? context.fetch(descriptor) else { return }
            write(books.first { $0.isInActiveLibrary && $0.lastPlayedAt != nil }, force: true)
        }
    }

    private func reload() {
        guard pendingReload == nil else { return }
        let remaining = max(0, 30 - Date.now.timeIntervalSince(lastReload))
        if remaining == 0 {
            lastReload = .now
            WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
        } else {
            pendingReload = Task { @MainActor in
                try? await Task.sleep(for: .seconds(remaining))
                lastReload = .now
                WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
                pendingReload = nil
            }
        }
    }

    private struct Snapshot: Encodable {
        let bookID: UUID
        let title: String
        let author: String
        let progress: Double
        let timeLeft: Double
        let lastPlayedAt: Date
    }
}
