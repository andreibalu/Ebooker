//
//  BackgroundSessionRoutingTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

@MainActor
struct BackgroundSessionRoutingTests {
    @Test func handlersAreConsumedOnlyByMatchingSessionIdentifier() {
        let registry = BackgroundSessionCompletionRegistry()
        var legacyCalls = 0
        var libriVoxCalls = 0
        registry.store({ legacyCalls += 1 }, for: "legacy")
        registry.store({ libriVoxCalls += 1 }, for: "librivox")

        registry.take(for: "librivox")?()

        #expect(legacyCalls == 0)
        #expect(libriVoxCalls == 1)
        #expect(registry.take(for: "librivox") == nil)
        registry.take(for: "legacy")?()
        #expect(legacyCalls == 1)
    }
}
