//
//  LibriVoxBackgroundDownloadCoordinatorTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

@MainActor
struct LibriVoxBackgroundDownloadCoordinatorTests {
    @Test func byteCallbackPublishesFractionWithoutIncrementingTrack() {
        let job = makeJob(trackCount: 2)
        let core = LibriVoxDownloadCoordinatorCore(jobs: [job])

        let event = core.progressEvent(
            identity: identity(job, track: 0),
            totalBytesWritten: 25,
            totalBytesExpected: 100
        )

        #expect(event == .progress(
            catalogID: "book",
            attemptID: job.attemptID,
            completed: 0,
            total: 2,
            currentTrackFraction: 0.25
        ))
    }

    @Test func unknownExpectedByteCountPublishesZeroFraction() {
        let job = makeJob(trackCount: 2)
        let core = LibriVoxDownloadCoordinatorCore(jobs: [job])

        let event = core.progressEvent(
            identity: identity(job, track: 0),
            totalBytesWritten: 25,
            totalBytesExpected: NSURLSessionTransferSizeUnknown
        )

        #expect(event == .progress(
            catalogID: "book",
            attemptID: job.attemptID,
            completed: 0,
            total: 2,
            currentTrackFraction: 0
        ))
    }

    @Test func completedTrackPersistsThenSchedulesNext() throws {
        let job = makeJob(trackCount: 2)
        var persisted: [LibriVoxDownloadJob] = []
        let core = LibriVoxDownloadCoordinatorCore(
            jobs: [job],
            persist: { persisted.append($0) }
        )

        let result = try core.markTrackCompleted(identity: identity(job, track: 0))

        #expect(persisted.last?.completedIndexes == [0])
        #expect(result?.transition == .schedule(trackIndex: 1))
        #expect(result?.event == .progress(
            catalogID: "book",
            attemptID: job.attemptID,
            completed: 1,
            total: 2,
            currentTrackFraction: 0
        ))
    }

    @Test func finalTrackRequestsFinalization() throws {
        var job = makeJob(trackCount: 2)
        job.completedIndexes = [0]
        let core = LibriVoxDownloadCoordinatorCore(jobs: [job])

        let result = try core.markTrackCompleted(identity: identity(job, track: 1))

        #expect(result?.transition == .finalize)
    }

    @Test func lateCallbackFromOldAttemptIsIgnored() throws {
        let job = makeJob(trackCount: 1)
        let core = LibriVoxDownloadCoordinatorCore(jobs: [job])
        let oldIdentity = LibriVoxDownloadTaskIdentity(
            catalogID: job.catalogID,
            attemptID: UUID(),
            trackIndex: 0
        )

        #expect(core.progressEvent(
            identity: oldIdentity,
            totalBytesWritten: 1,
            totalBytesExpected: 2
        ) == nil)
        #expect(try core.markTrackCompleted(identity: oldIdentity) == nil)
    }

    @Test func retryWithoutPersistedFailureRestartsPreparation() {
        let core = LibriVoxDownloadCoordinatorCore(jobs: [])

        #expect(core.retryDisposition(catalogID: "book") == .restartPreparation)
    }

    @Test func retryWithPersistedFailureResumesStagedJob() {
        var job = makeJob(trackCount: 1)
        job.phase = .failed
        let core = LibriVoxDownloadCoordinatorCore(jobs: [job])

        #expect(core.retryDisposition(catalogID: "book") == .resume(job))
    }

    private func identity(
        _ job: LibriVoxDownloadJob,
        track: Int
    ) -> LibriVoxDownloadTaskIdentity {
        .init(catalogID: job.catalogID, attemptID: job.attemptID, trackIndex: track)
    }

    private func makeJob(trackCount: Int) -> LibriVoxDownloadJob {
        .init(
            catalogID: "book",
            attemptID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: "Jane Eyre",
            target: .fresh,
            stagingFolderName: "stage",
            tracks: (0..<trackCount).map { index in
                .init(
                    title: "Track \(index)",
                    remoteURL: URL(string: "https://example.com/\(index).mp3")!,
                    durationSeconds: 60,
                    storedFileName: "\(index).mp3"
                )
            },
            completedIndexes: [],
            phase: .downloading,
            lastError: nil
        )
    }
}
