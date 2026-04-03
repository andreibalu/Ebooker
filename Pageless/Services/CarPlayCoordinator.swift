//
//  CarPlayCoordinator.swift
//  Pageless
//

import CarPlay
import SwiftData
import UIKit

/// CarPlay UI: library tabs (Favorites / All Books), playback via `CPNowPlayingTemplate`, non-AI moments named "CarPlay N".
@MainActor
final class CarPlayCoordinator: NSObject {
    private weak var interfaceController: CPInterfaceController?
    private let modelContainer: ModelContainer
    private let audioPlayer: AudioPlayerManager

    private let libraryViewModel = LibraryViewModel()
    private static let carPlayMomentSequenceKey = "carPlayMomentSequence"

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
        self.interfaceController = interfaceController
        audioPlayer.configure(modelContext: modelContainer.mainContext)
        applyPlaybackDefaultsFromStorage()
        let root = makeRootTemplate()
        interfaceController.setRootTemplate(root, animated: true) { [weak self] _, _ in
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

        let momentImage = UIImage(systemName: "bookmark.fill")?.withRenderingMode(.alwaysTemplate) ?? UIImage()
        let momentButton = CPNowPlayingImageButton(image: momentImage) { [weak self] _ in
            self?.saveCarPlayMoment()
        }

        let progressImage = UIImage(systemName: "flag.fill")?.withRenderingMode(.alwaysTemplate) ?? UIImage()
        let progressButton = CPNowPlayingImageButton(image: progressImage) { [weak self] _ in
            self?.audioPlayer.setProgressMarker()
        }

        return [rateButton, momentButton, progressButton]
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
        else { return }

        let sortRaw = UserDefaults.standard.string(forKey: "librarySortOption") ?? LibrarySortOption.recent.rawValue
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Audiobook>()
        guard let all = try? context.fetch(descriptor) else { return }

        let favoriteBooks = libraryViewModel.sorted(all.filter(\.isFavorite), by: sortRaw)
        let sortedAll = libraryViewModel.sorted(Array(all), by: sortRaw)

        favorites.updateSections([CPListSection(items: listItems(for: favoriteBooks), header: nil, sectionIndexTitle: nil)])
        allBooks.updateSections([CPListSection(items: listItems(for: sortedAll), header: nil, sectionIndexTitle: nil)])
    }

    private func listItems(for books: [Audiobook]) -> [CPListItem] {
        var items: [CPListItem] = []
        for book in books {
            let playItem = CPListItem(text: book.title, detailText: book.displayAuthor)
            let bookID = book.id
            playItem.handler = { [weak self] _, completion in
                guard let self else {
                    completion()
                    return
                }
                Task { @MainActor in
                    await self.playAudiobookFromList(id: bookID)
                    completion()
                }
            }
            items.append(playItem)

            if book.hasProgressPosition {
                let jumpDetail = Self.savedProgressDetail(for: book)
                let flagImage = UIImage(systemName: "flag.fill")?.withRenderingMode(.alwaysTemplate) ?? UIImage()
                let jumpItem = CPListItem(text: "Jump to saved progress", detailText: jumpDetail, image: flagImage)
                let jumpBookID = book.id
                jumpItem.handler = { [weak self] _, completion in
                    guard let self else {
                        completion()
                        return
                    }
                    Task { @MainActor in
                        await self.jumpToSavedProgressFromList(id: jumpBookID)
                        completion()
                    }
                }
                items.append(jumpItem)
            }
        }
        return items
    }

    private static func savedProgressDetail(for book: Audiobook) -> String {
        guard let idx = book.progressTrackIndex, let time = book.progressTime else { return "" }
        let tracks = book.sortedTracks
        let trackLabel = tracks.indices.contains(idx) ? tracks[idx].title : "Track"
        return "\(trackLabel) · \(TimeFormatter.clockString(seconds: time))"
    }

    private func playAudiobookFromList(id: UUID) async {
        guard let book = fetchAudiobook(id: id) else { return }
        await audioPlayer.startPlaybackFromSavedProgress(for: book, autoplay: true)
        presentNowPlayingIfNeeded()
    }

    private func jumpToSavedProgressFromList(id: UUID) async {
        guard let book = fetchAudiobook(id: id) else { return }
        await audioPlayer.jumpToSavedProgressMarker(in: book)
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
