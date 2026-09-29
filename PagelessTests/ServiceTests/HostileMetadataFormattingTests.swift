//
//  HostileMetadataFormattingTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

/// Remote metadata (Audiobookshelf / LibriVox) must never trap the formatters.
struct HostileMetadataFormattingTests {
    private static let hostile: [Double] = [
        1e308, -1e308, 1e22, .infinity, -.infinity, .nan, .greatestFiniteMagnitude, 9.3e18,
    ]

    @Test func timeFormatterIsTotal() {
        for value in Self.hostile {
            _ = TimeFormatter.durationSummary(seconds: value)
            _ = TimeFormatter.clockString(seconds: value)
            _ = ABSBookDetailView.durationText(value)
            let pct = TimeFormatter.percentValue(value)
            #expect((0...100).contains(pct))
        }
    }

    @Test func legitValuesUnchanged() {
        #expect(TimeFormatter.durationSummary(seconds: 3600 * 11 + 32 * 60) == "11h 32m")
        #expect(TimeFormatter.durationSummary(seconds: -5) == "0m")
        #expect(TimeFormatter.clockString(seconds: 3725) == "1:02:05")
        #expect(TimeFormatter.percentValue(0.426) == 43)
        #expect(ABSBookDetailView.durationText(45) == "under 1 min")
        #expect(ABSBookDetailView.durationText(3600 * 2) == "2 hr")
    }

    @Test func absProgressWithHugeFiniteValuesDecodesAndRendersSafely() throws {
        let json = """
        {"libraryItemId":"x","duration":1e308,"progress":1e308,"currentTime":1e308,"isFinished":false}
        """
        let p = try JSONDecoder().decode(ABSMediaProgress.self, from: Data(json.utf8))
        #expect(p.isInProgress)
        #expect(TimeFormatter.percentValue(p.progress) == 100)
        _ = ABSBookDetailView.durationText(p.duration)
    }

    @Test func libriVoxPlaytimeIsClamped() throws {
        let json = """
        {"id":"1","section_number":1,"title":"t","playtime":"1e22","listen_url":"https://x/y.mp3"}
        """
        let track = try JSONDecoder().decode(LibriVoxAPITrack.self, from: Data(json.utf8))
        #expect(track.durationSeconds == TimeFormatter.maxPlausibleSeconds)
        let json3 = """
        {"id":"1","section_number":1,"title":"t","playtime":"1e300:1e300:1e300","listen_url":"https://x/y.mp3"}
        """
        let t3 = try JSONDecoder().decode(LibriVoxAPITrack.self, from: Data(json3.utf8))
        #expect(t3.durationSeconds <= TimeFormatter.maxPlausibleSeconds)
        let ok = try JSONDecoder().decode(
            LibriVoxAPITrack.self,
            from: Data(#"{"id":"2","section_number":1,"title":"t","playtime":"01:02:03","listen_url":"u"}"#.utf8))
        #expect(ok.durationSeconds == 3723)
    }
}
