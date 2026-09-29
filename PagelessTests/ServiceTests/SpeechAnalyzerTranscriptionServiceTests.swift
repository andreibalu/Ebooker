//
//  SpeechAnalyzerTranscriptionServiceTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct SpeechAnalyzerTranscriptionServiceTests {
    @Test func bestMatchPrefersExactThenSameLanguageThenEnglish() {
        guard #available(iOS 26, *) else { return }
        func match(_ available: [String], for requested: String) -> String? {
            SpeechAnalyzerTranscriptionService.bestMatch(
                in: available.map(Locale.init(identifier:)),
                for: Locale(identifier: requested)
            )?.identifier(.bcp47)
        }

        #expect(match(["en_GB", "en_US", "fr_FR"], for: "en_US") == "en-US")
        #expect(match(["fr_FR", "en_GB"], for: "en_US") == "en-GB")
        #expect(match(["fr_FR", "en_US"], for: "ro_RO") == "en-US")
        #expect(match(["fr_FR"], for: "ro_RO") == nil)
    }
}
