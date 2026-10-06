//
//  EmbeddedChapterReader.swift
//  Pageless
//

import AVFoundation

/// Reads chapter markers embedded in an audio file (m4b/m4a chapter tracks, MP3 ID3 `CHAP`).
enum EmbeddedChapterReader {
    static func markers(from asset: AVAsset) async -> [ChapterMarker] {
        guard let locales = try? await asset.load(.availableChapterLocales), !locales.isEmpty else {
            return []
        }
        // Most audiobook files tag their chapters with the "und" (undetermined) language, which
        // never matches a device language, so `bestMatchingPreferredLanguages` alone returns no
        // chapters for them. Fall back to the first locale the file actually carries.
        var groups = (try? await asset.loadChapterMetadataGroups(
            bestMatchingPreferredLanguages: Locale.preferredLanguages
        )) ?? []
        if groups.isEmpty {
            for locale in locales {
                groups = (try? await asset.loadChapterMetadataGroups(
                    withTitleLocale: locale,
                    containingItemsWithCommonKeys: []
                )) ?? []
                if !groups.isEmpty { break }
            }
        }

        var markers: [ChapterMarker] = []
        for group in groups {
            let start = group.timeRange.start.seconds
            let duration = group.timeRange.duration.seconds
            guard start.isFinite else { continue }
            var title = ""
            for item in group.items where item.commonKey == .commonKeyTitle {
                if let value = try? await item.load(.stringValue) {
                    title = value
                    break
                }
            }
            markers.append(ChapterMarker(
                title: title,
                start: start,
                end: duration.isFinite ? start + duration : start
            ))
        }
        return markers
    }
}
