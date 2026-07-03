//
//  DownloadLiveActivityControllerTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

@MainActor
struct DownloadLiveActivityControllerTests {
    @Test func startsOnceThenUpdatesSameActivity() async {
        let client = MockDownloadActivityClient(isAuthorized: true)
        let controller = DownloadLiveActivityController(client: client, successDelay: .zero)

        await controller.synchronize(snapshot: downloading(0.2), appIsActive: true)
        await controller.synchronize(snapshot: downloading(0.4), appIsActive: true)

        #expect(client.startedStates.count == 1)
        #expect(client.updatedStates.map(\.progress) == [0.4])
    }

    @Test func doesNotStartWhileAppIsBackgrounded() async {
        let client = MockDownloadActivityClient(isAuthorized: true)
        let controller = DownloadLiveActivityController(client: client)

        await controller.synchronize(snapshot: downloading(0.2), appIsActive: false)

        #expect(client.startedStates.isEmpty)
    }

    @Test func disabledAuthorizationIsNoOp() async {
        let client = MockDownloadActivityClient(isAuthorized: false)
        let controller = DownloadLiveActivityController(client: client)

        await controller.synchronize(snapshot: downloading(0.2), appIsActive: true)

        #expect(client.startedStates.isEmpty)
    }

    @Test func failedStatePersistsUntilDismissed() async {
        let client = MockDownloadActivityClient(isAuthorized: true, hasActivity: true)
        let controller = DownloadLiveActivityController(client: client)

        await controller.synchronize(snapshot: failed(), appIsActive: false)

        #expect(client.updatedStates.last?.phase == .failed)
        #expect(client.endCalls.isEmpty)
    }

    @Test func completeUpdatesThenEndsImmediatelyAfterDelay() async {
        let client = MockDownloadActivityClient(isAuthorized: true, hasActivity: true)
        let controller = DownloadLiveActivityController(client: client, successDelay: .zero)

        await controller.synchronize(snapshot: complete(), appIsActive: false)

        #expect(client.updatedStates.last?.phase == .complete)
        #expect(client.endCalls == [true])
    }

    @Test func emptySnapshotEndsExistingActivityImmediately() async {
        let client = MockDownloadActivityClient(isAuthorized: true, hasActivity: true)
        let controller = DownloadLiveActivityController(client: client)

        await controller.synchronize(snapshot: nil, appIsActive: false)

        #expect(client.endCalls == [true])
    }

    private func downloading(_ progress: Double) -> DownloadActivitySnapshot {
        .init(
            title: "Jane Eyre",
            activeBookCount: 1,
            completedTracks: 1,
            totalTracks: 4,
            progress: progress,
            phase: .downloading,
            failureMessage: nil
        )
    }

    private func failed() -> DownloadActivitySnapshot {
        .init(
            title: "Download paused",
            activeBookCount: 1,
            completedTracks: 1,
            totalTracks: 4,
            progress: 0.25,
            phase: .failed,
            failureMessage: "Offline"
        )
    }

    private func complete() -> DownloadActivitySnapshot {
        .init(
            title: "Downloaded",
            activeBookCount: 1,
            completedTracks: 4,
            totalTracks: 4,
            progress: 1,
            phase: .complete,
            failureMessage: nil
        )
    }
}

@MainActor
private final class MockDownloadActivityClient: DownloadActivityClient {
    let isAuthorized: Bool
    var hasActivity: Bool
    private(set) var startedStates: [DownloadActivityAttributes.ContentState] = []
    private(set) var updatedStates: [DownloadActivityAttributes.ContentState] = []
    private(set) var endCalls: [Bool] = []

    init(isAuthorized: Bool, hasActivity: Bool = false) {
        self.isAuthorized = isAuthorized
        self.hasActivity = hasActivity
    }

    func start(
        attributes: DownloadActivityAttributes,
        state: DownloadActivityAttributes.ContentState
    ) throws {
        startedStates.append(state)
        hasActivity = true
    }

    func update(state: DownloadActivityAttributes.ContentState) async {
        updatedStates.append(state)
    }

    func end(state: DownloadActivityAttributes.ContentState?, immediate: Bool) async {
        endCalls.append(immediate)
        hasActivity = false
    }
}
