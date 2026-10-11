//
//  UnpagedRoute.swift
//  Pageless
//

import Foundation
import Observation

enum UnpagedRoute: Equatable, Sendable {
    case downloads
    case resume
    case library

    init?(url: URL) {
        guard url.scheme?.lowercased() == "unpaged" else { return nil }
        if url.host?.lowercased() == "resume", url.path.isEmpty || url.path == "/" {
            self = .resume
            return
        }
        if url.host?.lowercased() == "library", url.path.isEmpty || url.path == "/" {
            self = .library
            return
        }
        guard url.host?.lowercased() == "library",
              url.pathComponents == ["/", "downloads"]
        else { return nil }
        self = .downloads
    }
}

@MainActor
@Observable
final class UnpagedRouter {
    var pendingRoute: UnpagedRoute?

    func open(_ url: URL) {
        pendingRoute = UnpagedRoute(url: url)
    }

    func consume(_ route: UnpagedRoute) {
        if pendingRoute == route { pendingRoute = nil }
    }
}
