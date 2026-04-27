//
//  CarPlayCoordinator.swift
//  Pageless
//

import CarPlay
import OSLog
import SwiftData
import UIKit

private let carPlayLog = Logger(subsystem: "andreibaludev.Pageless", category: "CarPlay")

/// CarPlay UI: library tabs (Favorites / All Books), playback via `CPNowPlayingTemplate`, non-AI moments named "CarPlay N".
@MainActor
final class CarPlayCoordinator: NSObject {
    private weak var interfaceController: CPInterfaceController?
    private let modelContainer: ModelContainer
    private let audioPlayer: AudioPlayerManager

    private let libraryViewModel = LibraryViewModel()
    private static let carPlayMomentSequenceKey = "carPlayMomentSequence"

    private var momentButtonConfirmed = false
    private var progressButtonConfirmed = false

    private lazy var nowPlayingTemplate: CPNowPlayingTemplate = {
        let template = CPNowPlayingTemplate.shared
        template.updateNowPlayingButtons(makeNowPlayingButtons())
        return template
    }()

    init(modelContainer: ModelContainer, audioPlayer: AudioPlayerManager) {
        self.modelContainer = modelContainer
        self.audioPlayer = audioPlayer
        super.init()
    }

    func connect(interfaceController: CPInterfaceController) {
        carPlayLog.info("coordinator connect")
        self.interfaceController = interfaceController
        audioPlayer.configure(modelContext: modelContainer.mainContext)
        applyPlaybackDefaultsFromStorage()
        let root = makeRootTemplate()
        interfaceController.setRootTemplate(root, animated: true) { [weak self] success, error in
            if let error {
                carPlayLog.error("setRootTemplate failed: \(String(describing: error), privacy: .public)")
            } else {
                carPlayLog.info("setRootTemplate success=\(success, privacy: .public)")
            }
            self?.refreshLibraryTemplates()
        }
    }

    func disconnect() {
        interfaceController = nil
    }

    // MARK: - Templates

    private func makeRootTemplate() -> CPTemplate {
        let favorites = CPListTemplate(
            title: "Favorites",
            sections: [CPListSection(items: [], header: nil, sectionIndexTitle: nil)]
        )
        favorites.tabImage = UIImage(systemName: "heart.fill")

        let allBooks = CPListTemplate(
            title: "All Books",
            sections: [CPListSection(items: [], header: nil, sectionIndexTitle: nil)]
        )
        allBooks.tabImage = UIImage(systemName: "books.vertical.fill")

        let tabBar = CPTabBarTemplate(templates: [favorites, allBooks])
        tabBar.delegate = self
        return tabBar
    }

    private func makeNowPlayingButtons() -> [CPNowPlayingButton] {
        let rateButton = CPNowPlayingPlaybackRateButton { [weak self] _ in
            self?.cyclePlaybackRateForCarPlay()
        }

        let momentIconName = momentButtonConfirmed ? "checkmark.circle.fill" : "bookmark.fill"
        let momentImage = UIImage(systemName: momentIconName)?.withRenderingMode(.alwaysTemplate) ?? UIImage()
        let momentButton = CPNowPlayingImageButton(image: momentImage) { [weak self] _ in
            self?.handleMomentButton()
        }

        let progressIconName = progressButtonConfirmed ? "checkmark.circle.fill" : "flag.fill"
        let progressImage = UIImage(systemName: progressIconName)?.withRenderingMode(.alwaysTemplate) ?? UIImage()
        let progressButton = CPNowPlayingImageButton(image: progressImage) { [weak self] _ in
            self?.handleProgressButton()
        }

        return [rateButton, momentButton, progressButton]
    }

    private func handleMomentButton() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            saveCarPlayMoment()
            flashButtonConfirmation(moment: true)
        }
    }

    private func handleProgressButton() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            audioPlayer.setProgressMarker()
            flashButtonConfirmation(moment: false)
        }
    }

    private func flashButtonConfirmation(moment: Bool) {
        if moment { momentButtonConfirmed = true } else { progressButtonConfirmed = true }
        nowPlayingTemplate.updateNowPlayingButtons(makeNowPlayingButtons())
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            if moment { momentButtonConfirmed = false } else { progressButtonConfirmed = false }
            nowPlayingTemplate.updateNowPlayingButtons(makeNowPlayingButtons())
        }
    }

    private func cyclePlaybackRateForCarPlay() {
        let rates = AudioPlayerManager.supportedPlaybackRates
        guard let currentIndex = rates.firstIndex(of: audioPlayer.playbackRate) else {
            audioPlayer.setPlaybackRate(rates.first ?? 1)
            return
        }
        let next = rates[(currentIndex + 1) % rates.count]
        audioPlayer.setPlaybackRate(next)
        nowPlayingTemplate.updateNowPlayingButtons(makeNowPlayingButtons())
    }

    private func saveCarPlayMoment() {
        guard let audiobook = audioPlayer.currentAudiobook else { return }
        let backtrack = UserDefaults.standard.double(forKey: "momentBacktrackSeconds")
        let savedTime = max(audioPlayer.currentTime - backtrack, 0)
        let trackIndex = audioPlayer.currentTrackIndex

        let nextNumber = (UserDefaults.standard.integer(forKey: Self.carPlayMomentSequenceKey) % 999) + 1
        UserDefaults.standard.set(nextNumber, forKey: Self.carPlayMomentSequenceKey)

        let label = "CarPlay \(nextNumber)"
        let moment = Moment(
            trackIndex: trackIndex,
            time: savedTime,
            label: label,
            audiobook: audiobook,
            transcript: nil,
            aiGeneratedName: false,
            notes: nil
        )
        modelContainer.mainContext.insert(moment)
        try? modelContainer.mainContext.save()
    }

    private func applyPlaybackDefaultsFromStorage() {
        let defaults = UserDefaults.standard
        let resume: Double
        if defaults.object(forKey: "resumeBacktrackSeconds") != nil {
            resume = defaults.double(forKey: "resumeBacktrackSeconds")
        } else {
            resume = ResumeBacktrackOption.oneMinute.rawValue
        }
        let skipBack: Double
        if defaults.object(forKey: "skipBackSeconds") != nil {
            skipBack = defaults.double(forKey: "skipBackSeconds")
        } else {
            skipBack = SkipIntervalOption.thirty.rawValue
        }
        let skipForward: Double
        if defaults.object(forKey: "skipForwardSeconds") != nil {
            skipForward = defaults.double(forKey: "skipForwardSeconds")
        } else {
            skipForward = SkipIntervalOption.thirty.rawValue
        }
        audioPlayer.applyPlaybackDefaults(
            resumeBacktrack: resume,
            skipBack: skipBack,
            skipForward: skipForward
        )
    }

    private func refreshLibraryTemplates() {
        guard let tabBar = interfaceController?.rootTemplate as? CPTabBarTemplate,
              tabBar.templates.count >= 2,
              let favorites = tabBar.templates[0] as? CPListTemplate,
              let allBooks = tabBar.templates[1] as? CPListTemplate
        else {
            carPlayLog.error("refreshLibraryTemplates aborted: root template not as expected")
            return
        }

        let sortRaw = UserDefaults.standard.string(forKey: "librarySortOption") ?? LibrarySortOption.recent.rawValue
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Audiobook>()
        guard let all = try? context.fetch(descriptor) else {
            carPlayLog.error("refreshLibraryTemplates aborted: fetch failed")
            return
        }

        let favoriteBooks = libraryViewModel.sorted(all.filter(\.isFavorite), by: sortRaw)
        let sortedAll = libraryViewModel.sorted(Array(all), by: sortRaw)

        carPlayLog.info("refresh: favorites=\(favoriteBooks.count, privacy: .public) all=\(sortedAll.count, privacy: .public)")

        favorites.updateSections([CPListSection(items: listItems(for: favoriteBooks), header: nil, sectionIndexTitle: nil)])
        allBooks.updateSections([CPListSection(items: listItems(for: sortedAll), header: nil, sectionIndexTitle: nil)])
    }

    private func listItems(for books: [Audiobook]) -> [CPListItem] {
        books.map { book in
            let detail: String
            if book.hasProgressPosition, let idx = book.progressTrackIndex, let time = book.progressTime {
                let tracks = book.sortedTracks
                let trackLabel = tracks.indices.contains(idx) ? tracks[idx].title : "Track"
                detail = "\(trackLabel) · \(TimeFormatter.clockString(seconds: time))"
            } else {
                detail = book.displayAuthor
            }

            let item = CPListItem(text: book.title, detailText: detail)
            let bookID = book.id
            item.handler = { [weak self] _, completion in
                guard let self else { completion(); return }
                Task { @MainActor in
                    await self.playAudiobookFromList(id: bookID)
                    completion()
                }
            }
            return item
        }
    }

    private func playAudiobookFromList(id: UUID) async {
        guard let book = fetchAudiobook(id: id) else { return }
        await audioPlayer.startPlaybackFromSavedProgress(for: book, autoplay: true)
        presentNowPlayingIfNeeded()
    }

    private func fetchAudiobook(id: UUID) -> Audiobook? {
        let context = ModelContext(modelContainer)
        let bookID = id
        var descriptor = FetchDescriptor<Audiobook>(
            predicate: #Predicate<Audiobook> { $0.id == bookID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func presentNowPlayingIfNeeded() {
        guard let interfaceController else { return }
        nowPlayingTemplate.updateNowPlayingButtons(makeNowPlayingButtons())
        if interfaceController.topTemplate === nowPlayingTemplate { return }
        interfaceController.pushTemplate(nowPlayingTemplate, animated: true) { _, _ in }
    }
}

// MARK: - CPTabBarTemplateDelegate

extension CarPlayCoordinator: CPTabBarTemplateDelegate {
    nonisolated func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        Task { @MainActor in
            self.refreshLibraryTemplates()
        }
    }
}
