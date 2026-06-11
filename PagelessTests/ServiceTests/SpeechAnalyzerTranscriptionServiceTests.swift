//
//  SpeechAnalyzerTranscriptionServiceTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct SpeechAnalyzerTranscriptionServiceTests {
    @Test func bestMatchPrefersExactLocale() {
        guard #available(iOS 26, *) else { return }
        let locales = [Locale(identifier: "en_GB"), Locale(identifier: "en_US"), Locale(identifier: "fr_FR")]
        let match = SpeechAnalyzerTranscriptionService.bestMatch(in: locales, for: Locale(identifier: "en_US"))
        #expect(match?.identifier(.bcp47) == "en-US")
    }

    @Test func bestMatchFallsBackToSameLanguage() {
        guard #available(iOS 26, *) else { return }
        let locales = [Locale(identifier: "fr_FR"), Locale(identifier: "en_GB")]
        let match = SpeechAnalyzerTranscriptionService.bestMatch(in: locales, for: Locale(identifier: "en_US"))
        #expect(match?.identifier(.bcp47) == "en-GB")
    }

    @Test func bestMatchFallsBackToEnglish() {
        guard #available(iOS 26, *) else { return }
        let locales = [Locale(identifier: "fr_FR"), Locale(identifier: "en_US")]
        let match = SpeechAnalyzerTranscriptionService.bestMatch(in: locales, for: Locale(identifier: "ro_RO"))
        #expect(match?.identifier(.bcp47) == "en-US")
    }

    @Test func bestMatchReturnsNilWhenNothingFits() {
        guard #available(iOS 26, *) else { return }
        let locales = [Locale(identifier: "fr_FR")]
        let match = SpeechAnalyzerTranscriptionService.bestMatch(in: locales, for: Locale(identifier: "ro_RO"))
        #expect(match == nil)
    }
}
