//
//  DeviceDownloadStateTests.swift
//  PagelessTests
//
//  `DeviceDownloadState` is this device's only record that a book's audio is here, and files
//  appearing never flip a book back to downloaded. A background download session finishes,
//  calls the system's completion handler and can be suspended or killed at once, so the E2E
//  suite (which waits seconds between steps) can't see a lost write. Ways it can fail:
//
//  1. An explicit change is still only in memory when the process ends: the next launch reads
//     the old answer, and a downloaded book stays "In iCloud only" or streaming for good.
//  2. A rollback's restore is lost the same way, and the next launch sees the failed change.
//

import Foundation
import Testing
@testable import Pageless

struct DeviceDownloadStateTests {
    private func makeFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceDownloadStateTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("DeviceDownloadState.plist")
    }

    @Test func explicitChangeIsOnDiskWhenSetReturns() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = UUID()
        let state = DeviceDownloadState(fileURL: url)
        state.set(false, for: id)
        state.set(true, for: id)

        let relaunched = DeviceDownloadState(fileURL: url)
        #expect(relaunched.hasEntry(id))
        #expect(relaunched.isDownloaded(id) { false })
    }

    @Test func restoreIsOnDiskWhenItReturns() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let kept = UUID()
        let fresh = UUID()
        let state = DeviceDownloadState(fileURL: url)
        state.set(true, for: kept)
        let snapshot = state.snapshot([kept, fresh])
        state.set(false, for: kept)
        state.set(true, for: fresh)
        snapshot.restore()

        let relaunched = DeviceDownloadState(fileURL: url)
        #expect(relaunched.isDownloaded(kept) { false })
        #expect(!relaunched.hasEntry(fresh))
    }
}
