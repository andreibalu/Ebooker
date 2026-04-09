//
//  MockFreeBookDownloadService.swift
//  PagelessTests
//

import Foundation
@testable import Pageless

@MainActor
final class MockFreeBookDownloadService: FreeBookDownloading {
    var downloadProgress: [String: Double] = [:]
    var activeDownloads: Set<String> = []
    var downloadErrors: [String: String] = [:]
    var startDownloadCalled: [FreeBookCatalogEntry] = []
    var cancelDownloadCalled: [String] = []

    func startDownload(entry: FreeBookCatalogEntry) {
        startDownloadCalled.append(entry)
        activeDownloads.insert(entry.id)
        downloadProgress[entry.id] = 0.0
    }

    func cancelDownload(catalogId: String) {
        cancelDownloadCalled.append(catalogId)
        activeDownloads.remove(catalogId)
        downloadProgress.removeValue(forKey: catalogId)
    }
}
