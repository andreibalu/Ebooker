//
//  CarPlayCoordinator.swift
//  Pageless
//

import CarPlay
import OSLog
import SwiftData
import UIKit

private let carPlayLog = Logger(subsystem: "andreibaludev.Pageless", category: "CarPlay")

/// CarPlay UI: library tabs (Favorites / All Books / Free Books), playback via `CPNowPlayingTemplate`, non-AI moments named "CarPlay N".
@MainActor
final class CarPlayCoordinator: NSObject {
    private weak var interfaceController: CPInterfaceController?
    private let modelContainer: ModelContainer
    private let audioPlayer: AudioPlayerManager

    private let libraryViewModel = LibraryViewModel()
    private let freeBookDownloader: FreeBookDownloadService
    private let voiceSearch = CarPlayVoiceSearch()
    private static let carPlayMomentSequenceKey = "carPlayMomentSequence"

    private var freeBookCatalog: [FreeBookCatalogEntry] = []
    private weak var freeBooksTemplate: CPListTemplate?
    private var voiceTemplate: CPVoiceControlTemplate?

    private var momentButtonConfirmed = false
    private var progressButtonConfirmed = false

    private lazy var nowPlayingTemplate: CPNowPlayingTemplate = {
        let template = CPNowPlayingTemplate.shared
        template.updateNowPlayingButtons(makeNowPlayingButtons())
        return template
    }()

    init(modelContainer: ModelContainer, audioPlayer: AudioPlayerManager, freeBookDownloader: FreeBookDownloadService) {
        self.modelContainer = modelContainer
        self.audioPlayer = audioPlayer
        self.freeBookDownloader = freeBookDownloader
        super.init()
    }

    func connect(interfaceController: CPInterfaceController) {
        carPlayLog.info("coordinator connect")
        self.interfaceController = interfaceController
        audioPlayer.configure(modelContext: modelContainer.mainContext)
        freeBookDownloader.configure(modelContext: modelContainer.mainContext)
        applyPlaybackDefaultsFromStorage()
        let root = makeRootTemplate()
        interfaceController.setRootTemplate(root, animated: true) { [weak self] success, error in
            if let error {
                carPlayLog.error("setRootTemplate failed: \(String(describing: error), privacy: .public)")
            } else {
                carPlayLog.info("setRootTemplate success=\(success, privacy: .public)")
            }
            self?.refreshLibraryTemplates()
            self?.loadFreeBookCatalog()
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

        let freeBooks = CPListTemplate(
            title: "Free Books",
            sections: [CPListSection(items: [], header: nil, sectionIndexTitle: nil)]
        )
        freeBooks.tabImage = UIImage(systemName: "gift.fill")
        freeBooksTemplate = freeBooks

        let tabBar = CPTabBarTemplate(templates: [favorites, allBooks, freeBooks])
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

        // Mirror the iPhone grid: only books playable on this device — never cloud-only own
        // orphans or archived (user-removed) free books that live solely in the iCloud Library.
        let library = all.filter { ($0.isDownloaded || $0.isFreeBook) && !$0.isArchived }
        let favoriteBooks = libraryViewModel.sorted(library.filter(\.isFavorite), by: sortRaw)
        let sortedAll = libraryViewModel.sorted(library, by: sortRaw)

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

    // MARK: - Free Books Tab

    private func loadFreeBookCatalog() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let entries = await FreeBookCatalogService.allEntries()
            self.freeBookCatalog = entries
            self.refreshFreeBooksTemplate()
        }
    }

    private func refreshFreeBooksTemplate() {
        guard let template = freeBooksTemplate else { return }

        let voiceItem = CPListItem(
            text: "Search by voice",
            detailText: "Tap and say a title or author",
            image: UIImage(systemName: "mic.fill")
        )
        voiceItem.handler = { [weak self] _, completion in
            self?.startVoiceSearch()
            completion()
        }
        let voiceSection = CPListSection(items: [voiceItem], header: "Search", sectionIndexTitle: nil)

        let downloadedIds = downloadedFreeBookCatalogIds()
        let recommended = freeBookCatalog.filter { !downloadedIds.contains($0.id) }
        let recommendedItems = recommended.map { entry -> CPListItem in
            makeCatalogListItem(for: entry)
        }
        let recommendedSection: CPListSection
        if recommendedItems.isEmpty {
            let placeholder = CPListItem(
                text: freeBookCatalog.isEmpty ? "Loading recommendations…" : "All recommendations downloaded",
                detailText: nil
            )
            recommendedSection = CPListSection(items: [placeholder], header: "Recommended", sectionIndexTitle: nil)
        } else {
            recommendedSection = CPListSection(items: recommendedItems, header: "Recommended", sectionIndexTitle: nil)
        }

        template.updateSections([voiceSection, recommendedSection])
    }

    private func makeCatalogListItem(for entry: FreeBookCatalogEntry) -> CPListItem {
        let durationText = TimeFormatter.durationSummary(seconds: entry.totalDurationSeconds)
        let detail: String
        let isDownloading = freeBookDownloader.activeDownloads.contains(entry.id)
        if isDownloading, let progress = freeBookDownloader.downloadProgress[entry.id] {
            detail = "Downloading · \(Int(progress * 100))%"
        } else {
            detail = "\(entry.author) · \(durationText)"
        }
        let item = CPListItem(text: entry.title, detailText: detail, image: UIImage(systemName: "book.closed.fill"))
        let entryId = entry.id
        item.handler = { [weak self] _, completion in
            self?.handleCatalogTap(entryId: entryId)
            completion()
        }
        return item
    }

    private func handleCatalogTap(entryId: String) {
        guard let entry = freeBookCatalog.first(where: { $0.id == entryId }) else { return }
        if let existing = fetchAudiobook(catalogId: entryId) {
            Task { @MainActor in
                await audioPlayer.startPlaybackFromSavedProgress(for: existing, autoplay: true)
                presentNowPlayingIfNeeded()
            }
            return
        }
        guard NetworkMonitor.shared.isConnected else {
            presentInfoAlert(
                title: "You're offline",
                message: "Free books stream over the internet. Connect and try again."
            )
            return
        }
        Task { @MainActor in
            let audiobook = addCatalogEntryAsStreamingAudiobook(entry)
            await audioPlayer.startPlayback(for: audiobook, autoplay: true)
            presentNowPlayingIfNeeded()
        }
    }

    /// Inserts an Audiobook with `isDownloaded == false` whose tracks point at the
    /// catalog entry's remote URLs, so playback streams instead of waiting on a download.
    private func addCatalogEntryAsStreamingAudiobook(_ entry: FreeBookCatalogEntry) -> Audiobook {
        let context = modelContainer.mainContext
        let audiobook = Audiobook(
            title: entry.title,
            author: entry.author,
            folderName: UUID().uuidString,
            coverArtData: nil,
            totalDuration: entry.totalDurationSeconds,
            isFreeBook: true,
            catalogId: entry.id,
            isDownloaded: false
        )
        context.insert(audiobook)

        for trackEntry in entry.tracks {
            let safeTitle = trackEntry.title.isEmpty ? "Track \(trackEntry.orderIndex + 1)" : trackEntry.title
            let audioTrack = AudioTrack(
                title: safeTitle,
                originalFileName: trackEntry.fileName,
                storedFileName: "",
                orderIndex: trackEntry.orderIndex,
                duration: trackEntry.durationSeconds
            )
            audioTrack.remoteURLString = trackEntry.downloadURL
            audioTrack.audiobook = audiobook
            context.insert(audioTrack)
            audiobook.tracks.append(audioTrack)
        }

        try? context.save()
        return audiobook
    }

    private func downloadedFreeBookCatalogIds() -> Set<String> {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Audiobook>()
        guard let books = try? context.fetch(descriptor) else { return [] }
        return Set(books.compactMap(\.catalogId))
    }

    // MARK: - Voice Search

    private func startVoiceSearch() {
        guard let interfaceController else { return }

        // System permission prompts can't appear on the CarPlay display — they only
        // surface on the iPhone. If permissions weren't primed while the phone was
        // active, refuse mid-drive and tell the driver to enable it on their phone.
        switch VoiceSearchPermissions.status {
        case .granted:
            break
        case .notDetermined:
            presentInfoAlert(
                title: "Set up voice search on your iPhone",
                message: "Open Unpaged on your iPhone, then tap Free Books to grant microphone access. After that, voice search will work here."
            )
            return
        case .denied:
            presentInfoAlert(
                title: "Voice search needs permission",
                message: "Enable Microphone and Speech Recognition for Unpaged in iPhone Settings, then try again."
            )
            return
        }

        let listening = CPVoiceControlState(
            identifier: "listening",
            titleVariants: ["Listening… say a title or author"],
            image: nil,
            repeats: true
        )
        let thinking = CPVoiceControlState(
            identifier: "thinking",
            titleVariants: ["Searching free books…"],
            image: nil,
            repeats: true
        )
        let template = CPVoiceControlTemplate(voiceControlStates: [listening, thinking])
        voiceTemplate = template

        // CPVoiceControlTemplate is a modal template — pushing it raises an NSException.
        interfaceController.presentTemplate(template, animated: true) { [weak self] _, _ in
            template.activateVoiceControlState(withIdentifier: "listening")
            self?.runVoiceRecognition()
        }
    }

    private func runVoiceRecognition() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let query = try await self.voiceSearch.recognize()
                self.voiceTemplate?.activateVoiceControlState(withIdentifier: "thinking")
                try? await Task.sleep(for: .milliseconds(300))
                self.presentVoiceResults(query: query)
            } catch {
                carPlayLog.error("voice search failed: \(String(describing: error), privacy: .public)")
                self.popVoiceTemplate()
                self.presentInfoAlert(
                    title: "Couldn't search",
                    message: (error as? CarPlayVoiceSearch.VoiceError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
    }

    private func popVoiceTemplate() {
        guard let interfaceController, let template = voiceTemplate else { return }
        if interfaceController.presentedTemplate === template {
            interfaceController.dismissTemplate(animated: true) { _, _ in }
        }
        voiceTemplate = nil
    }

    private func presentVoiceResults(query: String) {
        guard let interfaceController else { return }
        let results = searchFreeBooks(matching: query)

        let items: [CPListItem]
        if results.isEmpty {
            let empty = CPListItem(text: "No matches for “\(query)”", detailText: "Try another title or author")
            items = [empty]
        } else {
            items = results.map { result in
                let item = CPListItem(
                    text: result.title,
                    detailText: result.subtitle,
                    image: UIImage(systemName: "book.fill")
                )
                let captured = result
                item.handler = { [weak self] _, completion in
                    self?.handleSearchResultTap(result: captured)
                    completion()
                }
                return item
            }
        }

        let section = CPListSection(items: items, header: "Results for “\(query)”", sectionIndexTitle: nil)
        let resultsTemplate = CPListTemplate(title: "Free Books", sections: [section])

        // Dismiss the modally-presented voice template before pushing the results
        // template onto the navigation stack, so the back arrow returns to Free Books.
        if interfaceController.presentedTemplate === voiceTemplate {
            interfaceController.dismissTemplate(animated: false) { [weak interfaceController] _, _ in
                interfaceController?.pushTemplate(resultsTemplate, animated: true) { _, _ in }
            }
        } else {
            interfaceController.pushTemplate(resultsTemplate, animated: true) { _, _ in }
        }
        voiceTemplate = nil
    }

    private struct FreeBookSearchResult: Sendable {
        enum Source: Sendable {
            case catalog(catalogId: String)
            case librivox(persistentId: PersistentIdentifier)
        }
        let title: String
        let subtitle: String
        let source: Source
    }

    private func searchFreeBooks(matching query: String) -> [FreeBookSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let needle = trimmed.lowercased()

        var results: [FreeBookSearchResult] = []

        // 1. Hardcoded catalog (always available)
        for entry in freeBookCatalog {
            if entry.title.lowercased().contains(needle) || entry.author.lowercased().contains(needle) {
                let durationText = TimeFormatter.durationSummary(seconds: entry.totalDurationSeconds)
                results.append(FreeBookSearchResult(
                    title: entry.title,
                    subtitle: "\(entry.author) · \(durationText)",
                    source: .catalog(catalogId: entry.id)
                ))
            }
        }

        // 2. Synced LibriVox catalog (large, optional)
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<LibriVoxBook> { book in
            book.title.localizedStandardContains(trimmed) ||
            book.authorDisplay.localizedStandardContains(trimmed)
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 25
        if let books = try? context.fetch(descriptor) {
            let existingTitles = Set(results.map { $0.title.lowercased() })
            for book in books {
                guard !existingTitles.contains(book.title.lowercased()) else { continue }
                let duration = book.totalTimeSecs > 0
                    ? TimeFormatter.durationSummary(seconds: Double(book.totalTimeSecs))
                    : "Unknown length"
                results.append(FreeBookSearchResult(
                    title: book.title,
                    subtitle: "\(book.authorDisplay) · \(duration)",
                    source: .librivox(persistentId: book.persistentModelID)
                ))
                if results.count >= 30 { break }
            }
        }

        return results
    }

    private func handleSearchResultTap(result: FreeBookSearchResult) {
        switch result.source {
        case .catalog(let catalogId):
            handleCatalogTap(entryId: catalogId)
        case .librivox(let persistentId):
            startLibriVoxStreaming(persistentId: persistentId)
        }
    }

    private func startLibriVoxStreaming(persistentId: PersistentIdentifier) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let context = self.modelContainer.mainContext
            guard let book = context.model(for: persistentId) as? LibriVoxBook else {
                self.presentInfoAlert(title: "Couldn't open book", message: "This book is no longer in the catalog.")
                return
            }

            // Reuse existing library entry if we already added this book.
            // `catalogId` is computed (wraps `_catalogId`), so #Predicate can't use it.
            if let existing = self.fetchAudiobook(catalogId: book.id) {
                // If it was removed (archived) but kept in iCloud, bring it back to the library.
                if existing.isArchived {
                    existing.isArchived = false
                    try? context.save()
                }
                await self.audioPlayer.startPlaybackFromSavedProgress(for: existing, autoplay: true)
                self.presentNowPlayingIfNeeded()
                return
            }

            do {
                let cached: [CachedLibriVoxTrack]
                if let existing = book.cachedTracks {
                    cached = existing
                } else {
                    let apiTracks = try await LibriVoxAPIClient.fetchTracks(projectID: book.id)
                    cached = apiTracks.enumerated().map { i, t in
                        CachedLibriVoxTrack(
                            title: t.title,
                            listenURL: t.listenURL,
                            durationSeconds: t.durationSeconds,
                            orderIndex: i
                        )
                    }
                    book.cachedTracks = cached
                    try? context.save()
                }
                guard !cached.isEmpty else {
                    self.presentInfoAlert(title: "Couldn't open book", message: "This book has no available tracks.")
                    return
                }
                let audiobook = try await StreamingLibraryService.addToLibrary(
                    book: book, tracks: cached, modelContext: context
                )
                await self.audioPlayer.startPlayback(for: audiobook, autoplay: true)
                self.presentNowPlayingIfNeeded()
            } catch {
                carPlayLog.error("librivox stream failed: \(String(describing: error), privacy: .public)")
                self.presentInfoAlert(title: "Couldn't open book", message: error.localizedDescription)
            }
        }
    }

    private func fetchAudiobook(catalogId: String) -> Audiobook? {
        // `Audiobook.catalogId` is a computed property over the private stored
        // `_catalogId`, so SwiftData's #Predicate keypath cache asserts on it.
        // Filter in memory instead — the library is small and fully fits.
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Audiobook>()
        guard let books = try? context.fetch(descriptor) else { return nil }
        return books.first(where: { $0.catalogId == catalogId })
    }

    // MARK: - Alerts

    private func presentInfoAlert(title: String, message: String) {
        guard let interfaceController else { return }
        let action = CPAlertAction(title: "OK", style: .default) { [weak interfaceController] _ in
            interfaceController?.dismissTemplate(animated: true) { _, _ in }
        }
        let alert = CPAlertTemplate(titleVariants: [title, message], actions: [action])
        interfaceController.presentTemplate(alert, animated: true) { _, _ in }
    }
}

// MARK: - CPTabBarTemplateDelegate

extension CarPlayCoordinator: CPTabBarTemplateDelegate {
    nonisolated func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        Task { @MainActor in
            self.refreshLibraryTemplates()
            self.refreshFreeBooksTemplate()
        }
    }
}
