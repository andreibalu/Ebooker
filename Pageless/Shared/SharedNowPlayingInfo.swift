//
//  SharedNowPlayingInfo.swift
//  Pageless
//

import Foundation
import UIKit

struct SharedNowPlayingInfo: Codable {
    let bookID: UUID
    let title: String
    let author: String
    let coverArtThumbnail: Data?
    let progress: Double
    let currentTrackTitle: String
    let isPlaying: Bool
    let playbackRate: Double
    let lastUpdated: Date

    static let suiteName = "group.andreibaludev.Pageless"
    static let key = "sharedNowPlayingInfo"

    static func save(_ info: SharedNowPlayingInfo) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: key)
    }

    static func load() -> SharedNowPlayingInfo? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SharedNowPlayingInfo.self, from: data)
    }

    static func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: key)
    }

    /// Downsample cover art to a 200x200 JPEG thumbnail for lightweight storage.
    static func makeThumbnail(from imageData: Data?, maxSize: CGFloat = 200) -> Data? {
        guard let imageData, let image = UIImage(data: imageData) else { return nil }
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.6)
    }
}
