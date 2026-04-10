//
//  FreeBookDownloading.swift
//  Pageless
//

import Foundation

@MainActor
protocol FreeBookDownloading: AnyObject {
    var downloadProgress: [String: Double] { get }
    var activeDownloads: Set<String> { get }
    var downloadErrors: [String: String] { get }
    func startDownload(entry: FreeBookCatalogEntry)
    func cancelDownload(catalogId: String)
}
