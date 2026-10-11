import Foundation
import SwiftData

nonisolated struct ABSDownloadJob: Codable, Sendable {
    struct Track: Codable, Sendable {
        let id: UUID
        let url: URL
        let name: String
    }
    let id: UUID
    let bookID: UUID
    let title: String
    let server: URL
    let username: String?
    let tracks: [Track]
    var completed: Set<Int> = []
    var error: String?
}

/// Sequential background transfers. A book is promoted only after all files are durable.
@MainActor
@Observable
final class ABSDownloadManager: NSObject {
    static let shared = ABSDownloadManager()
    nonisolated static let sessionIdentifier = "andreibaludev.Pageless.absDownloads"
    private(set) var jobs: [UUID: ABSDownloadJob] = [:]
    private(set) var fractions: [UUID: Double] = [:]
    private(set) var storageError: String?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var scheduling: Set<UUID> = []
    @ObservationIgnored private var preparing: Set<UUID> = []
    @ObservationIgnored nonisolated private let drain = BackgroundEventDrain()
    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    private var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ABSDownloads", isDirectory: true)
    }

    func configure(context: ModelContext) {
        self.context = context
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                where url.pathExtension == "json" {
                let job = try JSONDecoder().decode(ABSDownloadJob.self, from: Data(contentsOf: url))
                guard !job.tracks.isEmpty,
                      job.completed.allSatisfy({ job.tracks.indices.contains($0) }),
                      job.tracks.allSatisfy({ !AudiobookshelfLibraryService.containsCredential($0.url)
                          && !$0.name.isEmpty && URL(fileURLWithPath: $0.name).lastPathComponent == $0.name }) else {
                    storageError = "Unpaged couldn't restore a saved download."
                    continue
                }
                jobs[job.bookID] = job
            }
        } catch { storageError = "Unpaged couldn't restore saved downloads. Try again." }
        Task { await reconcile() }
    }

    func book(id: UUID) -> Audiobook? {
        guard let context else { return nil }
        return try? context.fetch(FetchDescriptor<Audiobook>(predicate: #Predicate { $0.id == id })).first
    }

    func progress(for bookID: UUID) -> Double {
        guard let job = jobs[bookID], !job.tracks.isEmpty else { return 0 }
        return min(1, (Double(job.completed.count) + (fractions[bookID] ?? 0)) / Double(job.tracks.count))
    }

    func start(_ book: Audiobook, client: AudiobookshelfClient? = nil) async {
        let client = client ?? ABSAccount.shared.client
        guard book.isAudiobookshelfBook, !book.isDownloaded, jobs[book.id] == nil, !preparing.contains(book.id) else { return }
        preparing.insert(book.id)
        defer { preparing.remove(book.id) }
        do {
            guard let connection = try await client.connection() else { throw AudiobookshelfError.notConnected }
            let tracks = try book.sortedTracks.enumerated().map { index, track -> ABSDownloadJob.Track in
                guard let url = track.remoteURL, !AudiobookshelfLibraryService.containsCredential(url) else {
                    throw AudiobookshelfError.invalidMediaURL
                }
                let ext = url.pathExtension.isEmpty ? "m4b" : url.pathExtension
                return .init(id: track.id, url: url, name: "\(index).\(ext)")
            }
            guard !tracks.isEmpty else { throw AudiobookshelfError.invalidMediaURL }
            let job = ABSDownloadJob(id: UUID(), bookID: book.id, title: book.title,
                                     server: connection.baseURL, username: connection.username, tracks: tracks)
            try persist(job)
            jobs[book.id] = job
            storageError = nil
            await schedule(job, client: client)
        } catch { storageError = ABSBookDetailViewModel.message(for: error) }
    }

    func retry(_ bookID: UUID) async {
        guard var job = jobs[bookID] else { return }
        job.error = nil
        if let book = book(id: bookID),
           let folder = try? LibriVoxDownloadService.storageFolderURL(named: book.folderName),
           !job.tracks.allSatisfy({ FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.name).path) }) {
            job.completed = job.completed.filter {
                FileManager.default.fileExists(atPath: staging(job).appendingPathComponent(job.tracks[$0].name).path)
            }
        }
        do {
            try persist(job)
            jobs[bookID] = job
            await schedule(job)
        } catch { fail(job, message: "Couldn't save this download. Free some storage and retry.") }
    }

    func cancel(_ bookID: UUID) async {
        guard let job = jobs.removeValue(forKey: bookID) else { return }
        fractions[bookID] = nil
        let tasks = await session.allTasks
        for task in tasks where task.taskDescription?.hasPrefix(job.id.uuidString + "|") == true { task.cancel() }
        do {
            try FileManager.default.removeItem(at: manifest(job))
            if FileManager.default.fileExists(atPath: staging(job).path) { try FileManager.default.removeItem(at: staging(job)) }
            if job.completed.count == job.tracks.count, let book = book(id: bookID), !book.isDownloaded {
                let folder = try LibriVoxDownloadService.storageFolderURL(named: book.folderName)
                if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            }
        } catch { storageError = "Couldn't remove the cancelled download's files." }
    }

    func removeDownload(_ book: Audiobook) async {
        await cancel(book.id)
        do {
            let folder = try LibriVoxDownloadService.storageFolderURL(named: book.folderName)
            // Move out of the library before changing metadata, so a failed save can restore it.
            let trash = root.appendingPathComponent("removed-\(UUID().uuidString)")
            let exists = FileManager.default.fileExists(atPath: folder.path)
            if exists { try FileManager.default.moveItem(at: folder, to: trash) }
            let downloaded = book.isDownloaded
            book.isDownloaded = false
            do { try context?.save() }
            catch {
                book.isDownloaded = downloaded
                if exists { try? FileManager.default.moveItem(at: trash, to: folder) }
                throw error
            }
            if exists { try FileManager.default.removeItem(at: trash) }
            storageError = nil
        } catch { storageError = "Couldn't remove this download. Try again." }
    }

    func removeAllDownloads() async {
        for id in Array(jobs.keys) { await cancel(id) }
        let books = (try? context?.fetch(FetchDescriptor<Audiobook>())) ?? []
        for book in books where book.isAudiobookshelfBook && book.isDownloaded { await removeDownload(book) }
    }

    func downloadedBytes() -> Int64 {
        let books = (try? context?.fetch(FetchDescriptor<Audiobook>())) ?? []
        return books.filter { $0.isAudiobookshelfBook && $0.isDownloaded }.reduce(0) { total, book in
            let folder = try? LibriVoxDownloadService.storageFolderURL(named: book.folderName)
            guard let folder, let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return total }
            var bytes: Int64 = 0
            for case let url as URL in files { bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            return total + bytes
        }
    }

    func reconcile() async {
        let tasks = await session.allTasks
        for task in tasks {
            guard let description = task.taskDescription, matching(description) != nil else { task.cancel(); continue }
        }
        for job in Array(jobs.values) where job.error == nil {
            if job.completed.count == job.tracks.count {
                await finalize(job)
            } else if !tasks.contains(where: { $0.taskDescription?.hasPrefix(job.id.uuidString + "|") == true }) {
                await schedule(job)
            }
        }
    }

    private func manifest(_ job: ABSDownloadJob) -> URL { root.appendingPathComponent(job.bookID.uuidString + ".json") }
    private func staging(_ job: ABSDownloadJob) -> URL { root.appendingPathComponent(job.id.uuidString, isDirectory: true) }
    private func persist(_ job: ABSDownloadJob) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(job).write(to: manifest(job), options: .atomic)
    }

    private func matching(_ description: String) -> (ABSDownloadJob, Int)? {
        let parts = description.split(separator: "|")
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])), let index = Int(parts[1]),
              let job = jobs.values.first(where: { $0.id == id }), job.tracks.indices.contains(index) else { return nil }
        return (job, index)
    }

    private func schedule(_ job: ABSDownloadJob, client: AudiobookshelfClient? = nil) async {
        let client = client ?? ABSAccount.shared.client
        guard jobs[job.bookID]?.id == job.id, !scheduling.contains(job.id) else { return }
        scheduling.insert(job.id)
        defer { scheduling.remove(job.id) }
        guard let index = job.tracks.indices.first(where: { !job.completed.contains($0) }) else { await finalize(job); return }
        do {
            guard let connection = try await client.connection(), connection.baseURL == job.server,
                  connection.username == job.username else { throw AudiobookshelfError.notConnected }
            let url = try await client.playbackURL(forStoredURL: job.tracks[index].url)
            guard jobs[job.bookID]?.id == job.id else { return }
            guard let active = try await client.connection(), active.baseURL == job.server,
                  active.username == job.username else { throw AudiobookshelfError.notConnected }
            guard jobs[job.bookID]?.id == job.id else { return }
            try FileManager.default.createDirectory(at: staging(job), withIntermediateDirectories: true)
            let task = session.downloadTask(with: url)
            task.taskDescription = "\(job.id.uuidString)|\(index)"
            task.resume()
        } catch { fail(job, message: ABSBookDetailViewModel.message(for: error)) }
    }

    private func fail(_ job: ABSDownloadJob, message: String) {
        guard var current = jobs[job.bookID], current.id == job.id else { return }
        current.error = message
        jobs[job.bookID] = current
        do { try persist(current) } catch { storageError = "Couldn't save download recovery information." }
    }

    private func receive(_ temporary: URL, description: String?, status: Int?) async {
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let description, let (savedJob, index) = matching(description) else { return }
        var job = savedJob
        guard status == 200 || status == 206,
              ((try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 else {
            fail(job, message: "The server couldn't send this audio. Retry when it is available.")
            return
        }
        do {
            let target = staging(job).appendingPathComponent(job.tracks[index].name)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: temporary, to: target)
            job.completed.insert(index)
            try persist(job)
            jobs[job.bookID] = job
            fractions[job.bookID] = 0
            await schedule(job)
        } catch { fail(job, message: "Couldn't store this audio. Free some storage and retry.") }
    }

    private func finalize(_ job: ABSDownloadJob) async {
        guard jobs[job.bookID]?.id == job.id, let book = book(id: job.bookID),
              Set(book.tracks.map(\.id)) == Set(job.tracks.map(\.id)) else {
            await cancel(job.bookID)
            return
        }
        do {
            let destination = try LibriVoxDownloadService.storageFolderURL(named: book.folderName)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: staging(job).path) {
                guard job.tracks.allSatisfy({ FileManager.default.fileExists(atPath: staging(job).appendingPathComponent($0.name).path) }) else {
                    throw AudiobookshelfError.invalidMediaURL
                }
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.moveItem(at: staging(job), to: destination)
            }
            guard job.tracks.allSatisfy({ FileManager.default.fileExists(atPath: destination.appendingPathComponent($0.name).path) }) else {
                throw AudiobookshelfError.invalidMediaURL
            }
            let oldNames = book.tracks.map { ($0, $0.storedFileName) }
            for track in book.tracks { track.storedFileName = job.tracks.first { $0.id == track.id }!.name }
            book.isDownloaded = true
            do { try context?.save() }
            catch {
                book.isDownloaded = false
                for (track, name) in oldNames { track.storedFileName = name }
                throw error
            }
            try FileManager.default.removeItem(at: manifest(job))
            jobs[job.bookID] = nil
            fractions[job.bookID] = nil
        } catch { fail(job, message: "Couldn't finish this download. Free some storage and retry.") }
    }

    nonisolated private func finish(_ token: BackgroundEventDrain.Token) {
        if drain.finishEvent(token) { deliverCompletion() }
    }

    nonisolated private func deliverCompletion() {
        Task { @MainActor [drain] in
            _ = drain.deliverIfReady {
                AppDelegate.shared?.requestBackgroundSessionCompletionHandler(for: Self.sessionIdentifier)?()
            }
        }
    }
}

extension ABSDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                               didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                               totalBytesExpectedToWrite: Int64) {
        let description = downloadTask.taskDescription
        Task { @MainActor in
            guard let description, let (job, _) = matching(description) else { return }
            fractions[job.bookID] = totalBytesExpectedToWrite > 0
                ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : 0
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                               didFinishDownloadingTo location: URL) {
        let token = drain.beginEvent()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let description = downloadTask.taskDescription
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
        do { try FileManager.default.moveItem(at: location, to: temporary) }
        catch {
            Task { @MainActor in
                defer { finish(token) }
                if let description, let (job, _) = matching(description) { fail(job, message: "Couldn't store the downloaded audio.") }
            }
            return
        }
        Task { @MainActor in
            defer { finish(token) }
            await receive(temporary, description: description, status: status)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil else { return }
        let token = drain.beginEvent()
        let description = task.taskDescription
        Task { @MainActor in
            defer { finish(token) }
            if let description, let (job, _) = matching(description) {
                fail(job, message: "Download interrupted. Check your server connection and retry.")
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if drain.markFinishEventsSeen() { deliverCompletion() }
    }
}
