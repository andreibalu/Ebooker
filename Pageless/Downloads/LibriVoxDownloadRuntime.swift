import Foundation

@MainActor
final class LibriVoxDownloadRuntime {
    let manager: LibriVoxDownloadManager

    init(
        coordinator: LibriVoxDownloadCoordinating,
        activityController: DownloadLiveActivityControlling,
        isAppActive: @escaping @MainActor () -> Bool = { true }
    ) {
        manager = LibriVoxDownloadManager(
            coordinator: coordinator,
            activityController: activityController,
            isAppActive: isAppActive
        )
    }
}
