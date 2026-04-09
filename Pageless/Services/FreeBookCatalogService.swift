//
//  FreeBookCatalogService.swift
//  Pageless
//

import Foundation

enum FreeBookCatalogService {
    private static var cachedEntries: [FreeBookCatalogEntry]?

    static func allEntries() -> [FreeBookCatalogEntry] {
        if let cached = cachedEntries { return cached }

        guard let url = Bundle.main.url(forResource: "FreeBookCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([FreeBookCatalogEntry].self, from: data)
        else {
            return []
        }

        cachedEntries = entries
        return entries
    }

    static func availableEntries(excluding downloadedCatalogIds: Set<String>) -> [FreeBookCatalogEntry] {
        allEntries().filter { !downloadedCatalogIds.contains($0.id) }
    }
}
