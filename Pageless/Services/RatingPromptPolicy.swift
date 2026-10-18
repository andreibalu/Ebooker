//
//  RatingPromptPolicy.swift
//  Pageless
//
//  Decides when the app may ask for an App Store rating. Pure functions over values, so the rules
//  are tested without UI. `RatingPromptModifier` gathers the inputs and makes the request.
//

import Foundation

/// What survives relaunch, kept by `RatingPromptStore`.
struct RatingPromptHistory: Equatable {
    var firstLaunch: Date?
    var lastRequestVersion: String?
    var lastRequestDate: Date?
    var lastFinishedBook: Date?
}

/// Listening totals taken from `ReadingSession` rows.
struct RatingPromptListening: Equatable {
    var totalMinutes: Int
    var distinctDays: Int
    var lastListened: Date?

    init(totalMinutes: Int, distinctDays: Int, lastListened: Date?) {
        self.totalMinutes = totalMinutes
        self.distinctDays = distinctDays
        self.lastListened = lastListened
    }

    init(sessions: [(date: Date, minutes: Int)], calendar: Calendar = .current) {
        totalMinutes = sessions.reduce(0) { $0 + $1.minutes }
        distinctDays = Set(sessions.map { calendar.startOfDay(for: $0.date) }).count
        lastListened = sessions.map(\.date).max()
    }
}

/// The app's state right now. Every flag must be calm for a request.
struct RatingPromptSituation: Equatable {
    var isOnboardingComplete: Bool
    var isSceneActive: Bool
    /// Any sheet, alert, picker or full-screen cover the window is presenting.
    var isModalPresented: Bool
    var isPlayerOpen: Bool
    var isPlaying: Bool
    var isCarPlayConnected: Bool
}

enum RatingPromptReason: Equatable {
    case finishedBook
    case listeningHabit
}

enum RatingPromptSkip: Equatable {
    case onboarding
    case sceneNotActive
    case modalPresented
    case playerBusy
    case carPlayConnected
    case alreadyRequestedThisVersion
    case requestedRecently
    case installTooNew
    case noPositiveMoment

    /// A limit that nothing in the current session can lift, so there is no reason to keep checking.
    var isTerminal: Bool {
        self == .alreadyRequestedThisVersion || self == .requestedRecently
    }
}

enum RatingPromptDecision: Equatable {
    case request(RatingPromptReason)
    case skip(RatingPromptSkip)

    var isSkip: Bool {
        if case .skip = self { return true }
        return false
    }
}

enum RatingPromptPolicy {
    /// The app has been installed this long. A first launch never asks.
    static let minimumInstallAge: TimeInterval = 2 * 86_400
    /// A finished book stays a positive moment this long.
    static let finishedBookWindow: TimeInterval = 2 * 86_400
    /// The habit signal: this much listening on this many different days, and still listening.
    static let habitMinutes = 180
    static let habitDays = 3
    static let habitRecency: TimeInterval = 3 * 86_400
    /// Apple allows three prompts a year per person. We stay under it with one per version and
    /// this gap between versions.
    static let minimumGapBetweenRequests: TimeInterval = 90 * 86_400

    /// `listening` is a closure because summing sessions is the only costly input.
    static func decide(
        history: RatingPromptHistory,
        listening: () -> RatingPromptListening,
        situation: RatingPromptSituation,
        appVersion: String,
        now: Date
    ) -> RatingPromptDecision {
        if !situation.isOnboardingComplete { return .skip(.onboarding) }
        if !situation.isSceneActive { return .skip(.sceneNotActive) }
        if situation.isModalPresented { return .skip(.modalPresented) }
        if situation.isPlayerOpen || situation.isPlaying { return .skip(.playerBusy) }
        if situation.isCarPlayConnected { return .skip(.carPlayConnected) }

        if history.lastRequestVersion == appVersion { return .skip(.alreadyRequestedThisVersion) }
        if let last = history.lastRequestDate {
            // A negative gap means the clock moved back; stay quiet rather than ask early.
            let gap = now.timeIntervalSince(last)
            if gap < minimumGapBetweenRequests { return .skip(.requestedRecently) }
        }
        guard let first = history.firstLaunch, now.timeIntervalSince(first) >= minimumInstallAge else {
            return .skip(.installTooNew)
        }

        if let finished = history.lastFinishedBook {
            let age = now.timeIntervalSince(finished)
            if age >= 0, age <= finishedBookWindow { return .request(.finishedBook) }
        }
        let summary = listening()
        if summary.totalMinutes >= habitMinutes, summary.distinctDays >= habitDays,
           let last = summary.lastListened, now.timeIntervalSince(last) <= habitRecency {
            return .request(.listeningHabit)
        }
        return .skip(.noPositiveMoment)
    }
}

/// Requires the same `.request` decision on two checks in a row. A sheet that has just finished
/// dismissing, or a book that has just finished, is calm for an instant before the next thing opens.
struct RatingPromptSettling {
    private var streak = 0

    mutating func observe(_ decision: RatingPromptDecision) -> Bool {
        guard case .request = decision else {
            streak = 0
            return false
        }
        streak += 1
        guard streak >= 2 else { return false }
        streak = 0
        return true
    }
}

/// UserDefaults-backed history. Keys are not synced to iCloud: the question is per device and per install.
struct RatingPromptStore {
    static let standard = RatingPromptStore(defaults: .standard)

    private enum Key {
        static let firstLaunch = "ratingPrompt.firstLaunch"
        static let requestVersion = "ratingPrompt.lastRequestVersion"
        static let requestDate = "ratingPrompt.lastRequestDate"
        static let finishedBook = "ratingPrompt.lastFinishedBook"
    }

    static var allKeys: [String] {
        [Key.firstLaunch, Key.requestVersion, Key.requestDate, Key.finishedBook]
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var history: RatingPromptHistory {
        RatingPromptHistory(
            firstLaunch: date(Key.firstLaunch),
            lastRequestVersion: defaults.string(forKey: Key.requestVersion),
            lastRequestDate: date(Key.requestDate),
            lastFinishedBook: date(Key.finishedBook))
    }

    /// Records the first launch once. Later calls keep the earliest date.
    func noteLaunch(now: Date = .now) {
        guard defaults.object(forKey: Key.firstLaunch) == nil else { return }
        defaults.set(now.timeIntervalSince1970, forKey: Key.firstLaunch)
    }

    func recordFinishedBook(now: Date = .now) {
        defaults.set(now.timeIntervalSince1970, forKey: Key.finishedBook)
    }

    func recordRequest(version: String, now: Date = .now) {
        defaults.set(version, forKey: Key.requestVersion)
        defaults.set(now.timeIntervalSince1970, forKey: Key.requestDate)
    }

    private func date(_ key: String) -> Date? {
        defaults.object(forKey: key) == nil ? nil : Date(timeIntervalSince1970: defaults.double(forKey: key))
    }
}
