//
//  MomentFallbackNamerTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

/// When the model can't name a passage, smart save still offers a name built from the
/// transcript, chapter and position. Ways it can go wrong: every fallback reads "Saved Moment",
/// a name picked from a single passing mention, and an empty chapter title producing a
/// dangling "in".
struct MomentFallbackNamerTests {
    private let transcript = """
    Elizabeth turned the letter over twice before she opened it. Jane watched her from the window. \
    "It is from Mr. Darcy," Elizabeth said at last, and her voice was steady. Elizabeth read it slowly.
    """

    @Test func leadCharacterAndChapterNameTheMoment() {
        let analysis = MomentFallbackNamer.analysis(transcript: transcript, chapterTitle: "Chapter 34", time: 754)
        #expect(analysis.name == "Elizabeth in Chapter 34")
        #expect(analysis.characters.first == "Elizabeth")
        #expect(analysis.note.isEmpty)
        #expect(analysis.quoteLine == nil)
    }

    /// The name tagger's language asset is missing on simulators, and may be on a device.
    @Test func capitalizedWordsStandInForTheNameTagger() {
        let names = MomentFallbackNamer.capitalizedNames(in: transcript)
        #expect(names.first?.name == "Elizabeth")
        #expect(names.first?.mentions == 3)
        #expect(names.contains { $0.name == "Mr. Darcy" })
        // "Jane" only ever opens a sentence, so it can't be told from an ordinary word.
        #expect(!names.contains { $0.name == "Jane" })
    }

    @Test func chapterAndTimeWhenNoCharacterRecurs() {
        let analysis = MomentFallbackNamer.analysis(transcript: "The rain fell on the empty road.", chapterTitle: "Chapter 2", time: 754)
        #expect(analysis.name == "Chapter 2 at 12:34")
    }

    /// First-person narration has no names, but "I'm" is capitalized mid-sentence.
    @Test func firstPersonContractionsAreNotNames() {
        let text = "He looked at me. \"Well, I'm not sure,\" I said, and I'm certain he heard. Later I'm alone, and I'll wait."
        #expect(!MomentFallbackNamer.capitalizedNames(in: text).contains { $0.name.hasPrefix("I") })
    }

    @Test func timeAloneWithoutTranscriptOrChapter() {
        let analysis = MomentFallbackNamer.analysis(transcript: nil, chapterTitle: "  ", time: 3_725)
        #expect(analysis.name == "Moment at 1:02:05")
    }
}
