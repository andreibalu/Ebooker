//
//  FreeBookDownloadService.swift
//  Pageless
//

import Foundation
import SwiftData
import UIKit

@MainActor
@Observable
final class FreeBookDownloadService: FreeBookDownloading {
    // MARK: - Published State

    var downloadProgress: [String: Double] = [:]
    var activeDownloads: Set<String> = []
    var downloadErrors: [String: String] = [:]

    // MARK: - Internal State

    private var sessionDelegate: SessionDelegate?
    private var backgroundSession: URLSession?
    private var taskContexts: [Int: DownloadTaskContext] = [:]
    private var bookDownloadState: [String: BookDownloadState] = [:]
    private var pendingQueue: [FreeBookCatalogEntry] = []
    private var modelContext: ModelContext?

    struct DownloadTaskContext {
        let catalogId: String
        let trackEntry: FreeBookTrackEntry
        let folderName: String
    }

    struct BookDownloadState {
        let catalogEntry: FreeBookCatalogEntry
        let folderName: String
        var completedTracks: Int
        var totalTracks: Int
    }

    // MARK: - Configure

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        guard backgroundSession == nil else { return }
        let delegate = SessionDelegate(service: self)
        self.sessionDelegate = delegate
        let config = URLSessionConfiguration.background(withIdentifier: "com.ebooker.freeBookDownloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        self.backgroundSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - Public API

    func startDownload(entry: FreeBookCatalogEntry) {
        guard !activeDownloads.contains(entry.id) else { return }

        guard checkDiskSpace(requiredMB: entry.downloadSizeMB) else {
            downloadErrors[entry.id] = "Not enough storage space. This book requires \(Int(entry.downloadSizeMB)) MB."
            return
        }

        if !activeDownloads.isEmpty {
            pendingQueue.append(entry)
            return
        }

        beginDownload(entry: entry)
    }

    func cancelDownload(catalogId: String) {
        activeDownloads.remove(catalogId)
        downloadProgress.removeValue(forKey: catalogId)
        bookDownloadState.removeValue(forKey: catalogId)
        pendingQueue.removeAll { $0.id == catalogId }

        let tasksToCancel = taskContexts.filter { $0.value.catalogId == catalogId }
        for (taskId, _) in tasksToCancel {
            taskContexts.removeValue(forKey: taskId)
        }

        backgroundSession?.getAllTasks { tasks in
            for task in tasks {
                if tasksToCancel.keys.contains(task.taskIdentifier) {
                    task.cancel()
                }
            }
        }
    }

    // MARK: - Finalization

    func finalizeDownload(
        catalogEntry: FreeBookCatalogEntry,
        folderName: String,
        coverData: Data?,
        modelContext: ModelContext
    ) throws {
        let audiobook = Audiobook(
            title: catalogEntry.title,
            author: catalogEntry.author,
            folderName: folderName,
            coverArtData: coverData,
            totalDuration: catalogEntry.totalDurationSeconds,
            isFreeBook: true,
            catalogId: catalogEntry.id
        )
        modelContext.insert(audiobook)

        for track in catalogEntry.tracks {
            let storedFileName = String(format: "%03d", track.orderIndex + 1) + "-" + track.fileName
            let savedTrack = AudioTrack(
                title: track.title,
                originalFileName: track.fileName,
                storedFileName: storedFileName,
                orderIndex: track.orderIndex,
                duration: track.durationSeconds,
                audiobook: audiobook
            )
            audiobook.tracks.append(savedTrack)
            modelContext.insert(savedTrack)
        }

        audiobook.totalDuration = audiobook.sortedTracks.reduce(0) { $0 + $1.duration }
        try modelContext.save()
    }

    // MARK: - Delegate Callbacks

    func handleDownloadFinished(taskId: Int, location: URL) {
        guard let context = taskContexts[taskId] else { return }

        do {
            let folderURL = try storageFolderURL(for: context.folderName)
            let storedFileName = String(format: "%03d", context.trackEntry.orderIndex + 1) + "-" + context.trackEntry.fileName
            let destinationURL = folderURL.appendingPathComponent(storedFileName)

            if FileManager.default.fileExists(atPath: destinationURL.path()) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)

            taskContexts.removeValue(forKey: taskId)
            handleTrackCompletion(catalogId: context.catalogId)
        } catch {
            downloadErrors[context.catalogId] = "Download failed: \(error.localizedDescription)"
            activeDownloads.remove(context.catalogId)
            downloadProgress.removeValue(forKey: context.catalogId)
        }
    }

    func handleDownloadError(taskId: Int, error: Error) {
        guard let context = taskContexts[taskId] else { return }
        let catalogId = context.catalogId

        downloadErrors[catalogId] = error.localizedDescription
        activeDownloads.remove(catalogId)
        downloadProgress.removeValue(forKey: catalogId)
        bookDownloadState.removeValue(forKey: catalogId)

        // Cancel and remove all remaining task contexts for this book so
        // their completions don't attempt to finalize a partially-downloaded book.
        let orphanTaskIds = taskContexts.compactMap { $0.value.catalogId == catalogId ? $0.key : nil }
        for id in orphanTaskIds { taskContexts.removeValue(forKey: id) }
        backgroundSession?.getAllTasks { tasks in
            for task in tasks where orphanTaskIds.contains(task.taskIdentifier) {
                task.cancel()
            }
        }
    }

    // MARK: - Private

    private func beginDownload(entry: FreeBookCatalogEntry) {
        let folderName = UUID().uuidString
        activeDownloads.insert(entry.id)
        downloadProgress[entry.id] = 0.0
        downloadErrors.removeValue(forKey: entry.id)

        bookDownloadState[entry.id] = BookDownloadState(
            catalogEntry: entry,
            folderName: folderName,
            completedTracks: 0,
            totalTracks: entry.tracks.count
        )

        guard let backgroundSession else {
            activeDownloads.remove(entry.id)
            downloadProgress.removeValue(forKey: entry.id)
            bookDownloadState.removeValue(forKey: entry.id)
            downloadErrors[entry.id] = "Download service not ready."
            return
        }
        for track in entry.tracks {
            guard let url = URL(string: track.downloadURL) else { continue }
            let task = backgroundSession.downloadTask(with: url)
            taskContexts[task.taskIdentifier] = DownloadTaskContext(
                catalogId: entry.id,
                trackEntry: track,
                folderName: folderName
            )
            task.resume()
        }
    }

    private func handleTrackCompletion(catalogId: String) {
        guard var state = bookDownloadState[catalogId] else { return }
        state.completedTracks += 1
        bookDownloadState[catalogId] = state

        let progress = Double(state.completedTracks) / Double(state.totalTracks)
        downloadProgress[catalogId] = progress

        if state.completedTracks >= state.totalTracks {
            completeBookDownload(catalogId: catalogId, state: state)
        }
    }

    private func completeBookDownload(catalogId: String, state: BookDownloadState) {
        guard let modelContext else { return }

        do {
            try finalizeDownload(
                catalogEntry: state.catalogEntry,
                folderName: state.folderName,
                coverData: nil,
                modelContext: modelContext
            )
        } catch {
            downloadErrors[catalogId] = "Failed to save audiobook: \(error.localizedDescription)"
        }

        activeDownloads.remove(catalogId)
        downloadProgress.removeValue(forKey: catalogId)
        bookDownloadState.removeValue(forKey: catalogId)

        if let next = pendingQueue.first {
            pendingQueue.removeFirst()
            beginDownload(entry: next)
        }
    }

    private func checkDiskSpace(requiredMB: Double) -> Bool {
        let fileManager = FileManager.default
        guard let attrs = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSpace = attrs[.systemFreeSize] as? Int64
        else {
            return true
        }
        let requiredBytes = Int64(requiredMB * 1_048_576)
        return freeSpace > Int64(Double(requiredBytes) * 1.1)
    }

    private func storageFolderURL(for folderName: String) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let libraryURL = applicationSupport.appendingPathComponent("Audiobooks", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let audiobookFolderURL = libraryURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: audiobookFolderURL, withIntermediateDirectories: true)
        return audiobookFolderURL
    }
}

// MARK: - URLSession Delegate (separate NSObject)

private final class SessionDelegate: NSObject, URLSessionDownloadDelegate {
    private weak var service: FreeBookDownloadService?

    init(service: FreeBookDownloadService) {
        self.service = service
        super.init()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskId = downloadTask.taskIdentifier

        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let error = URLError(.badServerResponse)
            Task { @MainActor [weak self] in
                self?.service?.handleDownloadError(taskId: taskId, error: error)
            }
            return
        }

        // Copy file to temp location before it gets cleaned up
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
        try? FileManager.default.moveItem(at: location, to: tempURL)

        Task { @MainActor [weak self] in
            self?.service?.handleDownloadFinished(taskId: taskId, location: tempURL)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let taskId = task.taskIdentifier
        Task { @MainActor [weak self] in
            self?.service?.handleDownloadError(taskId: taskId, error: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Track completion count used for progress instead of byte-level
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            if let appDelegate = await UIApplication.shared.delegate as? AppDelegate {
                appDelegate.backgroundSessionCompletionHandler?()
                appDelegate.backgroundSessionCompletionHandler = nil
            }
        }
    }
}
