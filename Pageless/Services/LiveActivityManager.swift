//
//  LiveActivityManager.swift
//  Pageless
//

import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    private var currentActivity: Activity<PagelessPlaybackAttributes>?

    func startOrUpdate(
        bookTitle: String,
        author: String,
        bookID: String,
        trackTitle: String,
        currentTime: Double,
        duration: Double,
        isPlaying: Bool,
        progress: Double
    ) {
        let state = PagelessPlaybackAttributes.ContentState(
            trackTitle: trackTitle,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            progress: progress
        )

        if let activity = currentActivity {
            Task {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        } else {
            let attributes = PagelessPlaybackAttributes(
                bookTitle: bookTitle,
                author: author,
                bookID: bookID
            )
            let content = ActivityContent(state: state, staleDate: nil)
            do {
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                // Live Activities not available on this device
            }
        }
    }

    func stop() {
        guard let activity = currentActivity else { return }
        let finalState = PagelessPlaybackAttributes.ContentState(
            trackTitle: "",
            currentTime: 0,
            duration: 1,
            isPlaying: false,
            progress: 0
        )
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        currentActivity = nil
    }
}
