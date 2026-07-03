//
//  UnpagedRouteTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

@MainActor
struct UnpagedRouteTests {
    @Test func parsesDownloadActivityURL() {
        #expect(UnpagedRoute(url: URL(string: "unpaged://library/downloads")!) == .downloads)
    }

    @Test func rejectsUnknownURL() {
        #expect(UnpagedRoute(url: URL(string: "unpaged://library/other")!) == nil)
        #expect(UnpagedRoute(url: URL(string: "https://example.com")!) == nil)
    }
}
