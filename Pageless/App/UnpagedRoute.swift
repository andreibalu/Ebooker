//
//  UnpagedRoute.swift
//  Pageless
//

import Foundation
import Observation

enum UnpagedRoute: Equatable, Sendable {
    case downloads

    init?(url: URL) {
        guard url.scheme?.lowercased() == "unpaged",
              url.host?.lowercased() == "library",
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
