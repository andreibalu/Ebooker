//
//  DeviceDownloadState.swift
//  Pageless
//

import Foundation
import Observation

/// Whether each book's audio is downloaded on THIS device, keyed by `Audiobook.id`. It never syncs:
/// the synced `Audiobook` record is shared by every device, so a flag on it let one device's
/// download or removal move another device's books in or out of its library.
///
/// A plist in Application Support caches the answer. Without an entry (first launch after the
/// update, a record that just arrived from iCloud, a lost write) the answer comes from the files
/// in `Application Support/Audiobooks/<folderName>/`, so the cache can always be rebuilt from disk.
nonisolated final class DeviceDownloadState: Observable, @unchecked Sendable {
    static let shared = DeviceDownloadState(fileURL: defaultFileURL())

    private let fileURL: URL?
    private let lock = NSLock()
    private let writeLock = NSLock()
    private let registrar = ObservationRegistrar()
    private let saveQueue = DispatchQueue(label: "andreibaludev.Pageless.DeviceDownloadState", qos: .utility)
    private var entries: [UUID: Bool]
    private var saveScheduled = false
    private var storedRevision = 0

    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let raw = try? PropertyListDecoder().decode([String: Bool].self, from: data) {
            entries = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        } else {
            entries = [:]
        }
    }

    /// Bumped on every change, so SwiftUI views that read `Audiobook.isDownloaded` redraw.
    var revision: Int {
        registrar.access(self, keyPath: \.revision)
        return lock.withLock { storedRevision }
    }

    /// The cached answer, or `fallback()` (the files on disk), which is then cached.
    func isDownloaded(_ id: UUID, fallback: () -> Bool) -> Bool {
        _ = revision
        if let value = lock.withLock({ entries[id] }) { return value }
        let value = fallback()
        let inserted = lock.withLock {
            guard entries[id] == nil else { return false }
            entries[id] = value
            return true
        }
        if inserted { scheduleSave() }
        return value
    }

    func hasEntry(_ id: UUID) -> Bool {
        lock.withLock { entries[id] != nil }
    }

    func set(_ value: Bool, for id: UUID) {
        let changed = lock.withLock {
            let changed = entries[id] != value
            entries[id] = value
            return changed
        }
        guard changed else { return }
        // Written now, not batched: a background download finishes, calls the system's completion
        // handler and is suspended or killed at once, and a lost `true` never comes back (files
        // appearing never flip a book to downloaded).
        save()
        notify()
    }

    /// Drops entries for books that no longer exist.
    func retainOnly(_ ids: Set<UUID>) {
        let removed = lock.withLock {
            let before = entries.count
            entries = entries.filter { ids.contains($0.key) }
            return before != entries.count
        }
        if removed { scheduleSave() }
    }

    /// The values to put back when a library mutation rolls back its SwiftData changes;
    /// `ModelContext.rollback()` can't see this store.
    struct Snapshot {
        fileprivate let values: [UUID: Bool?]
        fileprivate let state: DeviceDownloadState

        func restore() {
            for (id, value) in values {
                if let value {
                    state.set(value, for: id)
                } else {
                    state.lock.withLock { _ = state.entries.removeValue(forKey: id) }
                    state.save()
                    state.notify()
                }
            }
        }
    }

    func snapshot(_ ids: [UUID]) -> Snapshot {
        Snapshot(values: lock.withLock {
            Dictionary(ids.map { ($0, entries[$0]) }, uniquingKeysWith: { first, _ in first })
        }, state: self)
    }

    #if DEBUG
    /// E2E only: forgets every answer, as on the first launch after the update.
    func e2eForgetAll() {
        lock.withLock { entries = [:] }
        scheduleSave()
        notify()
    }
    #endif

    // MARK: - Private

    private func notify() {
        let bump: @Sendable () -> Void = { [self] in
            registrar.withMutation(of: self, keyPath: \.revision) {
                lock.withLock { storedRevision &+= 1 }
            }
        }
        if Thread.isMainThread { bump() } else { DispatchQueue.main.async(execute: bump) }
    }

    private func scheduleSave() {
        guard fileURL != nil else { return }
        let shouldSchedule = lock.withLock {
            guard !saveScheduled else { return false }
            saveScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        saveQueue.asyncAfter(deadline: .now() + 0.2) { [self] in
            lock.withLock { saveScheduled = false }
            save()
        }
    }

    /// Writes the current entries. Taking the snapshot inside `writeLock` keeps a slower, older
    /// write from landing after a newer one.
    private func save() {
        guard let fileURL else { return }
        writeLock.withLock {
            let raw = lock.withLock {
                Dictionary(uniqueKeysWithValues: entries.map { ($0.key.uuidString, $0.value) })
            }
            guard let data = try? PropertyListEncoder().encode(raw) else { return }
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func defaultFileURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        #if DEBUG
        // Fixture launches keep their own copy beside the fixture store, which a reset deletes.
        if ProcessInfo.processInfo.arguments.contains("-e2e-fixture")
            || UserDefaults.standard.bool(forKey: "e2e.stickyFixture") {
            return support.appendingPathComponent("E2EFixtures", isDirectory: true)
                .appendingPathComponent("DeviceDownloadState.plist")
        }
        #endif
        return support.appendingPathComponent("DeviceDownloadState.plist")
    }
}
