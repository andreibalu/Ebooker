#if DEBUG
import Foundation

/// Stands in for the iCloud Drive container on fixture launches. A folder in the fixture store
/// plays the container, and file states advance on a clock: a copied-in file uploads over
/// `uploadSeconds`, and a file listed in `remote-only.json` (as if another device uploaded it)
/// downloads over `downloadSeconds` once asked. A nil root reads as iCloud Drive turned off.
nonisolated final class E2ECloudAudioBackend: CloudAudioBackend, @unchecked Sendable {
    private let root: URL?
    private let remoteOnlyURL: URL?
    private let uploadSeconds: Double
    private let downloadSeconds: Double
    private let quotaFull: Bool
    private let anotherDeviceCopiesFirst: Bool
    private let rootDelaySeconds: Double
    private let lock = NSLock()
    private var uploadStarts: [String: Date] = [:]
    private var downloadStarts: [String: Date] = [:]
    private var remoteOnly: Set<String>

    init(root: URL?, uploadSeconds: Double, downloadSeconds: Double, quotaFull: Bool,
         anotherDeviceCopiesFirst: Bool = false, rootDelaySeconds: Double = 0) {
        self.root = root
        self.anotherDeviceCopiesFirst = anotherDeviceCopiesFirst
        self.rootDelaySeconds = rootDelaySeconds
        self.remoteOnlyURL = root?.deletingLastPathComponent().appendingPathComponent("remote-only.json")
        self.uploadSeconds = uploadSeconds
        self.downloadSeconds = downloadSeconds
        self.quotaFull = quotaFull
        if let remoteOnlyURL, let data = try? Data(contentsOf: remoteOnlyURL),
           let keys = try? JSONDecoder().decode([String].self, from: data) {
            remoteOnly = Set(keys)
        } else {
            remoteOnly = []
        }
    }

    /// Marks files as uploaded by another device and not yet on this one.
    static func writeRemoteOnly(_ keys: [String], root: URL) throws {
        let url = root.deletingLastPathComponent().appendingPathComponent("remote-only.json")
        try JSONEncoder().encode(keys).write(to: url, options: .atomic)
    }

    func audiobooksRoot() async -> URL? {
        if rootDelaySeconds > 0 { try? await Task.sleep(for: .seconds(rootDelaySeconds)) }
        guard let root else { return nil }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func copyIn(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if anotherDeviceCopiesFirst, !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            // Another device's copy of the same file lands first; this copy then fails as it would.
            try FileManager.default.copyItem(at: source, to: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        lock.withLock { uploadStarts[key(destination)] = .now }
    }

    func hasSameFile(at destination: URL, as source: URL) -> Bool {
        func size(_ url: URL) -> Int64? {
            ((try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.size] as? NSNumber)?
                .int64Value
        }
        guard let existing = size(destination) else { return false }
        return existing == size(source)
    }

    func remove(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
        let prefix = key(url)
        lock.withLock {
            let matches: (String) -> Bool = { prefix.isEmpty || $0 == prefix || $0.hasPrefix("\(prefix)/") }
            remoteOnly = remoteOnly.filter { !matches($0) }
            uploadStarts = uploadStarts.filter { !matches($0.key) }
            downloadStarts = downloadStarts.filter { !matches($0.key) }
            persistRemoteOnly()
        }
    }

    func startDownloading(_ url: URL) throws {
        lock.withLock {
            let key = key(url)
            if remoteOnly.contains(key), downloadStarts[key] == nil { downloadStarts[key] = .now }
        }
    }

    func evict(_ url: URL) throws {
        lock.withLock {
            remoteOnly.insert(key(url))
            persistRemoteOnly()
        }
    }

    func copyOut(_ source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    @MainActor
    func startMonitoring(
        root: URL,
        onChange: @escaping @MainActor ([String: CloudAudioFileStatus]) -> Void
    ) -> CloudAudioMonitoring {
        E2ECloudAudioMonitor(backend: self, onChange: onChange)
    }

    func statuses() -> [String: CloudAudioFileStatus] {
        guard let root else { return [:] }
        let fileManager = FileManager.default
        let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let now = Date.now
        return lock.withLock {
            var result: [String: CloudAudioFileStatus] = [:]
            for folder in folders where folder.hasDirectoryPath {
                let names = (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
                for name in names where !name.hasPrefix(".") {
                    let key = CloudAudioPlan.key(folder.lastPathComponent, name)
                    let size = ((try? fileManager.attributesOfItem(
                        atPath: folder.appendingPathComponent(name).path(percentEncoded: false)
                    ))?[.size] as? NSNumber)?.int64Value ?? 0
                    var status = CloudAudioFileStatus(
                        size: size, isUploaded: true, uploadFraction: 1, isDownloaded: true, downloadFraction: 1
                    )
                    if let start = uploadStarts[key] {
                        let fraction = now.timeIntervalSince(start) / uploadSeconds
                        if quotaFull {
                            status.isUploaded = false
                            status.uploadFraction = 0
                            status.uploadError = .quotaExceeded
                        } else if fraction < 1 {
                            status.isUploaded = false
                            status.uploadFraction = fraction
                        } else {
                            uploadStarts[key] = nil
                        }
                    }
                    if remoteOnly.contains(key) {
                        status.isDownloaded = false
                        status.downloadFraction = 0
                        if let start = downloadStarts[key] {
                            let fraction = now.timeIntervalSince(start) / downloadSeconds
                            if fraction < 1 {
                                status.downloadFraction = fraction
                            } else {
                                downloadStarts[key] = nil
                                remoteOnly.remove(key)
                                persistRemoteOnly()
                                status.isDownloaded = true
                                status.downloadFraction = 1
                            }
                        }
                    }
                    result[key] = status
                }
            }
            return result
        }
    }

    /// `"<folder>/<file>"` relative to the root; empty for the root itself.
    private func key(_ url: URL) -> String {
        guard let root else { return "" }
        let rootParts = root.standardizedFileURL.pathComponents
        let parts = url.standardizedFileURL.pathComponents
        guard parts.starts(with: rootParts) else { return "" }
        return parts.dropFirst(rootParts.count).joined(separator: "/")
    }

    /// Callers hold `lock`.
    private func persistRemoteOnly() {
        guard let remoteOnlyURL else { return }
        try? JSONEncoder().encode(remoteOnly.sorted()).write(to: remoteOnlyURL, options: .atomic)
    }
}

@MainActor
final class E2ECloudAudioMonitor: CloudAudioMonitoring {
    private let backend: E2ECloudAudioBackend
    private let onChange: @MainActor ([String: CloudAudioFileStatus]) -> Void
    private var timer: Timer?

    init(backend: E2ECloudAudioBackend, onChange: @escaping @MainActor ([String: CloudAudioFileStatus]) -> Void) {
        self.backend = backend
        self.onChange = onChange
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        let statuses = backend.statuses()
        onChange(statuses)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
#endif
