//
//  DownloadLiveActivityController.swift
//  Pageless
//

import ActivityKit
import Foundation
import OSLog

@MainActor
protocol DownloadLiveActivityControlling: AnyObject {
    func synchronize(snapshot: DownloadActivitySnapshot?, appIsActive: Bool) async
}

@MainActor
protocol DownloadActivityClient: AnyObject {
    var isAuthorized: Bool { get }
    var hasActivity: Bool { get }
    func start(
        attributes: DownloadActivityAttributes,
        state: DownloadActivityAttributes.ContentState
    ) throws
    func update(state: DownloadActivityAttributes.ContentState) async
    func end(state: DownloadActivityAttributes.ContentState?, immediate: Bool) async
}

@MainActor
final class DownloadLiveActivityController: DownloadLiveActivityControlling {
    private let client: DownloadActivityClient
    private let successDelay: Duration
    private var generation = 0

    init(successDelay: Duration = .seconds(2)) {
        client = ActivityKitDownloadActivityClient()
        self.successDelay = successDelay
    }

    init(client: DownloadActivityClient, successDelay: Duration = .seconds(2)) {
        self.client = client
        self.successDelay = successDelay
    }

    func synchronize(snapshot: DownloadActivitySnapshot?, appIsActive: Bool) async {
        generation &+= 1
        let currentGeneration = generation
        guard let snapshot else {
            if client.hasActivity { await client.end(state: nil, immediate: true) }
            return
        }

        let state = snapshot.contentState
        if client.hasActivity {
            await client.update(state: state)
            if snapshot.phase == .complete {
                try? await Task.sleep(for: successDelay)
                guard generation == currentGeneration, client.hasActivity else { return }
                await client.end(state: state, immediate: true)
            }
            return
        }

        guard snapshot.phase == .preparing || snapshot.phase == .downloading,
              appIsActive,
              client.isAuthorized
        else { return }
        do {
            try client.start(
                attributes: .init(startedAt: .now),
                state: state
            )
        } catch {
            Logger.downloadActivity.error(
                "Could not start Live Activity: \(error.localizedDescription, privacy: .private)"
            )
        }
    }
}

@MainActor
final class ActivityKitDownloadActivityClient: DownloadActivityClient {
    private var activity: Activity<DownloadActivityAttributes>?

    var isAuthorized: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var hasActivity: Bool { resolvedActivity != nil }

    func start(
        attributes: DownloadActivityAttributes,
        state: DownloadActivityAttributes.ContentState
    ) throws {
        guard resolvedActivity == nil else { return }
        activity = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func update(state: DownloadActivityAttributes.ContentState) async {
        guard let activity = resolvedActivity else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end(state: DownloadActivityAttributes.ContentState?, immediate: Bool) async {
        guard let activity = resolvedActivity else { return }
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        await activity.end(
            content,
            dismissalPolicy: immediate ? .immediate : .default
        )
        self.activity = nil
    }

    private var resolvedActivity: Activity<DownloadActivityAttributes>? {
        if let activity { return activity }
        let restored = Activity<DownloadActivityAttributes>.activities.first
        activity = restored
        return restored
    }
}

private extension Logger {
    static let downloadActivity = Logger(
        subsystem: "andreibaludev.Pageless",
        category: "DownloadActivity"
    )
}
