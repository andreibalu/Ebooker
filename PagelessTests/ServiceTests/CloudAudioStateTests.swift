//
//  CloudAudioStateTests.swift
//  PagelessTests
//
//  `CloudAudioState.derive` decides what Unpaged promises about a book's audio in iCloud: the
//  "Remove from this iPhone" copy says the audio stays in iCloud, and Cloud Library offers
//  Download instead of Locate…. The E2E fake uploads every file in one step, so it can't produce
//  the mixed per-file states the iCloud Drive metadata query reports on a device. Ways it can fail:
//
//  1. `.stored` while a file is still uploading: the user removes the only local copy too early.
//  2. `.stored` while a track's file is missing from iCloud: Download yields an incomplete book.
//  3. Files from another book whose folder shares a prefix, or a same-named file in another
//     folder, count toward this book.
//  4. A book with no tracks counts as `.stored` (vacuous truth): Download "restores" nothing.
//  5. Stale files left in the folder, which no track references, make an incomplete book look whole.
//  6. A quota error hides behind `.uploading` forever, so the user never learns iCloud is full.
//  7. A book with nothing in iCloud reports `.partial`, which offers the wrong action.
//  8. Missing files while this device is still copying them read as `.partial`, not `.uploading`.
//
//  `CloudAudioPlan.filesToCopy` resumes interrupted uploads on every device. It must list only
//  missing files, never overwrite or delete, because another device may be mid-upload of a newer
//  copy (a race no simulator run can show).
//

import Foundation
import Testing
@testable import Pageless

struct CloudAudioStateTests {
    private func uploaded(_ size: Int64 = 100) -> CloudAudioFileStatus {
        CloudAudioFileStatus(size: size, isUploaded: true, uploadFraction: 1, isDownloaded: true, downloadFraction: 1)
    }

    private func uploading(_ fraction: Double, size: Int64 = 100) -> CloudAudioFileStatus {
        CloudAudioFileStatus(size: size, isUploaded: false, uploadFraction: fraction, isDownloaded: true, downloadFraction: 1)
    }

    private func derive(
        _ tracks: [String],
        _ files: [String: CloudAudioFileStatus],
        copying: Bool = false
    ) -> CloudAudioState {
        CloudAudioState.derive(folderName: "BOOK", trackFileNames: tracks, files: files, isCopying: copying)
    }

    @Test func aFileStillUploadingIsNotStored() {
        let state = derive(["a.m4b", "b.m4b"], ["BOOK/a.m4b": uploaded(), "BOOK/b.m4b": uploading(0.5)])
        #expect(state == .uploading(fraction: 0.75))
    }

    @Test func aMissingTrackFileIsNotStored() {
        #expect(derive(["a.m4b", "b.m4b"], ["BOOK/a.m4b": uploaded()]) == .partial)
    }

    @Test func otherFoldersNeverCount() {
        let files = ["BOOK-2/a.m4b": uploaded(), "OTHER/b.m4b": uploaded(), "BOOK/a.m4b": uploaded()]
        #expect(derive(["a.m4b", "b.m4b"], files) == .partial)
        #expect(derive(["a.m4b"], ["BOOK-2/a.m4b": uploaded()]) == .none)
    }

    @Test func aBookWithoutTracksIsNeverStored() {
        #expect(derive([], ["BOOK/a.m4b": uploaded()]) == .none)
    }

    @Test func staleFilesDoNotCompleteABook() {
        let files = ["BOOK/old-1.m4b": uploaded(), "BOOK/old-2.m4b": uploaded(), "BOOK/a.m4b": uploaded()]
        #expect(derive(["a.m4b", "b.m4b"], files) == .partial)
    }

    @Test func aQuotaErrorSurfacesOverUploading() {
        var full = uploading(0.2)
        full.uploadError = .quotaExceeded
        #expect(derive(["a.m4b", "b.m4b"], ["BOOK/a.m4b": uploading(0.4), "BOOK/b.m4b": full]) == .quotaExceeded)
        var failed = uploading(0)
        failed.uploadError = .other
        #expect(derive(["a.m4b"], ["BOOK/a.m4b": failed]) == .failed)
    }

    @Test func nothingInICloudIsNone() {
        #expect(derive(["a.m4b"], [:]) == .none)
        #expect(derive(["a.m4b"], [:], copying: true) == .uploading(fraction: 0))
    }

    @Test func missingFilesWhileCopyingAreUploading() {
        #expect(derive(["a.m4b", "b.m4b"], ["BOOK/a.m4b": uploaded()], copying: true) == .uploading(fraction: 0.5))
    }

    @Test func everyTrackUploadedIsStored() {
        #expect(derive(["a.m4b", "b.m4b"], ["BOOK/a.m4b": uploaded(), "BOOK/b.m4b": uploaded(300)]) == .stored)
    }

    @Test func resumeCopiesOnlyMissingFiles() {
        let files = ["BOOK/a.m4b": uploaded(1), "BOOK/stale.m4b": uploaded(), "OTHER/b.m4b": uploaded()]
        // a.m4b differs in size from the local copy but is never overwritten; stale.m4b stays.
        #expect(CloudAudioPlan.filesToCopy(folderName: "BOOK", trackFileNames: ["a.m4b", "b.m4b"], files: files)
            == ["b.m4b"])
    }
}
