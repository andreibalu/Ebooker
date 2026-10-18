//
//  RatingPromptPolicyTests.swift
//  PagelessTests
//
//  Failure list these tests were written from (each is a way the prompt could annoy a listener
//  or silently never fire). E2E (`e2e/tests/rating-prompt.e2e.ts`) covers the wiring; these cover
//  the rules, which E2E can reach only slowly.
//
//   1. Asks on the first launch day, or when the first launch was never recorded.
//   2. Asks while onboarding is on screen.
//   3. Asks while the scene is inactive or in the background.
//   4. Asks over a sheet, alert, paywall or file picker.
//   5. Asks while the full player is open or audio is playing.
//   6. Asks while a CarPlay scene is connected.
//   7. Asks twice in one app version, including after a relaunch.
//   8. Asks again soon after the last request when a new version ships.
//   9. Asks with no positive moment: no finished book, too little listening, listening on one day.
//  10. Treats a finished book from last week, or a lapsed listener, as a positive moment.
//  11. Boundary values (exactly two days, exactly 180 minutes) land on the wrong side.
//  12. A backward clock jump leaves the prompt permanently on or permanently off.
//  13. A state that is calm for one instant (a sheet that has just dismissed) asks.
//  14. The store forgets a request after relaunch, or `noteLaunch` overwrites the first launch.

import Foundation
import Testing
@testable import Pageless

@MainActor
struct RatingPromptPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private var calmSituation: RatingPromptSituation {
        RatingPromptSituation(
            isOnboardingComplete: true, isSceneActive: true, isModalPresented: false,
            isPlayerOpen: false, isPlaying: false, isCarPlayConnected: false)
    }

    private func history(
        installedDaysAgo: Double? = 10,
        finishedHoursAgo: Double? = 1,
        requestedVersion: String? = nil,
        requestedDaysAgo: Double? = nil
    ) -> RatingPromptHistory {
        RatingPromptHistory(
            firstLaunch: installedDaysAgo.map { now.addingTimeInterval(-$0 * day) },
            lastRequestVersion: requestedVersion,
            lastRequestDate: requestedDaysAgo.map { now.addingTimeInterval(-$0 * day) },
            lastFinishedBook: finishedHoursAgo.map { now.addingTimeInterval(-$0 * 3600) })
    }

    private let quiet = RatingPromptListening(totalMinutes: 20, distinctDays: 1, lastListened: nil)

    private func decide(
        _ history: RatingPromptHistory,
        listening: RatingPromptListening? = nil,
        situation: RatingPromptSituation? = nil,
        version: String = "1.6.0"
    ) -> RatingPromptDecision {
        RatingPromptPolicy.decide(
            history: history, listening: { listening ?? quiet }, situation: situation ?? calmSituation,
            appVersion: version, now: now)
    }

    // MARK: Positive moments

    @Test func finishedBookRecentlyAsks() {
        #expect(decide(history()) == .request(.finishedBook))
    }

    @Test func listeningHabitAsks() {
        let habit = RatingPromptListening(totalMinutes: 240, distinctDays: 4, lastListened: now.addingTimeInterval(-day))
        #expect(decide(history(finishedHoursAgo: nil), listening: habit) == .request(.listeningHabit))
    }

    @Test func noPositiveMomentSkips() {
        #expect(decide(history(finishedHoursAgo: nil)) == .skip(.noPositiveMoment))
    }

    @Test func finishedBookFromLastWeekIsNotAMoment() {
        #expect(decide(history(finishedHoursAgo: 24 * 7)) == .skip(.noPositiveMoment))
    }

    @Test func habitNeedsSeveralDays() {
        let oneDay = RatingPromptListening(totalMinutes: 600, distinctDays: 2, lastListened: now)
        #expect(decide(history(finishedHoursAgo: nil), listening: oneDay) == .skip(.noPositiveMoment))
    }

    @Test func habitNeedsMeaningfulMinutes() {
        let thin = RatingPromptListening(totalMinutes: 60, distinctDays: 5, lastListened: now)
        #expect(decide(history(finishedHoursAgo: nil), listening: thin) == .skip(.noPositiveMoment))
    }

    @Test func lapsedListenerIsNotAHabit() {
        let lapsed = RatingPromptListening(totalMinutes: 600, distinctDays: 9, lastListened: now.addingTimeInterval(-10 * day))
        #expect(decide(history(finishedHoursAgo: nil), listening: lapsed) == .skip(.noPositiveMoment))
    }

    @Test func habitBoundaryValuesCount() {
        let edge = RatingPromptListening(
            totalMinutes: RatingPromptPolicy.habitMinutes, distinctDays: RatingPromptPolicy.habitDays,
            lastListened: now.addingTimeInterval(-RatingPromptPolicy.habitRecency))
        #expect(decide(history(finishedHoursAgo: nil), listening: edge) == .request(.listeningHabit))
        let under = RatingPromptListening(
            totalMinutes: RatingPromptPolicy.habitMinutes - 1, distinctDays: RatingPromptPolicy.habitDays, lastListened: now)
        #expect(decide(history(finishedHoursAgo: nil), listening: under) == .skip(.noPositiveMoment))
    }

    @Test func finishedBookWindowBoundary() {
        let edge = history(finishedHoursAgo: RatingPromptPolicy.finishedBookWindow / 3600)
        #expect(decide(edge) == .request(.finishedBook))
        let past = history(finishedHoursAgo: RatingPromptPolicy.finishedBookWindow / 3600 + 0.01)
        #expect(decide(past) == .skip(.noPositiveMoment))
    }

    @Test func finishedBookInTheFutureIsIgnored() {
        #expect(decide(history(finishedHoursAgo: -5)) == .skip(.noPositiveMoment))
    }

    // MARK: Install age

    @Test func firstLaunchDayNeverAsks() {
        #expect(decide(history(installedDaysAgo: 0.2)) == .skip(.installTooNew))
    }

    @Test func unrecordedFirstLaunchNeverAsks() {
        #expect(decide(history(installedDaysAgo: nil)) == .skip(.installTooNew))
    }

    @Test func installAgeBoundary() {
        let days = RatingPromptPolicy.minimumInstallAge / day
        #expect(decide(history(installedDaysAgo: days)) == .request(.finishedBook))
        #expect(decide(history(installedDaysAgo: days - 0.01)) == .skip(.installTooNew))
    }

    @Test func firstLaunchInTheFutureNeverAsks() {
        #expect(decide(history(installedDaysAgo: -3)) == .skip(.installTooNew))
    }

    // MARK: Moment of the session

    @Test func onboardingBlocks() {
        var situation = calmSituation
        situation.isOnboardingComplete = false
        #expect(decide(history(), situation: situation) == .skip(.onboarding))
    }

    @Test func inactiveSceneBlocks() {
        var situation = calmSituation
        situation.isSceneActive = false
        #expect(decide(history(), situation: situation) == .skip(.sceneNotActive))
    }

    @Test func presentedModalBlocks() {
        var situation = calmSituation
        situation.isModalPresented = true
        #expect(decide(history(), situation: situation) == .skip(.modalPresented))
    }

    @Test func openPlayerBlocks() {
        var situation = calmSituation
        situation.isPlayerOpen = true
        #expect(decide(history(), situation: situation) == .skip(.playerBusy))
    }

    @Test func playingAudioBlocks() {
        var situation = calmSituation
        situation.isPlaying = true
        #expect(decide(history(), situation: situation) == .skip(.playerBusy))
    }

    @Test func carPlayBlocks() {
        var situation = calmSituation
        situation.isCarPlayConnected = true
        #expect(decide(history(), situation: situation) == .skip(.carPlayConnected))
    }

    // MARK: Limits

    @Test func onceAppVersion() {
        let asked = history(requestedVersion: "1.6.0", requestedDaysAgo: 200)
        #expect(decide(asked, version: "1.6.0") == .skip(.alreadyRequestedThisVersion))
    }

    @Test func newVersionStillWaitsForTheGap() {
        let recent = history(requestedVersion: "1.5.1", requestedDaysAgo: 30)
        #expect(decide(recent, version: "1.6.0") == .skip(.requestedRecently))
    }

    @Test func newVersionAsksAfterTheGap() {
        let old = history(requestedVersion: "1.5.1", requestedDaysAgo: RatingPromptPolicy.minimumGapBetweenRequests / day)
        #expect(decide(old, version: "1.6.0") == .request(.finishedBook))
    }

    @Test func requestDatedInTheFutureCountsAsRecent() {
        let skewed = history(requestedVersion: "1.5.1", requestedDaysAgo: -2)
        #expect(decide(skewed, version: "1.6.0") == .skip(.requestedRecently))
    }

    @Test func limitSkipsAreTerminal() {
        #expect(RatingPromptSkip.alreadyRequestedThisVersion.isTerminal)
        #expect(RatingPromptSkip.requestedRecently.isTerminal)
        #expect(!RatingPromptSkip.modalPresented.isTerminal)
        #expect(!RatingPromptSkip.noPositiveMoment.isTerminal)
        #expect(!RatingPromptSkip.installTooNew.isTerminal)
    }

    @Test func listeningIsOnlyComputedWhenNeeded() {
        var computed = 0
        let decision = RatingPromptPolicy.decide(
            history: history(), listening: { computed += 1; return quiet },
            situation: calmSituation, appVersion: "1.6.0", now: now)
        #expect(decision == .request(.finishedBook))
        #expect(computed == 0)
    }

    // MARK: Listening summary

    @Test func listeningSummaryCountsDistinctCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.startOfDay(for: now)
        let summary = RatingPromptListening(
            sessions: [
                (start, 30), (start.addingTimeInterval(3600 * 5), 20),
                (start.addingTimeInterval(-day), 45), (start.addingTimeInterval(-3 * day), 10),
            ],
            calendar: calendar)
        #expect(summary.totalMinutes == 105)
        #expect(summary.distinctDays == 3)
        #expect(summary.lastListened == start.addingTimeInterval(3600 * 5))
        #expect(RatingPromptListening(sessions: [], calendar: calendar).lastListened == nil)
    }

    // MARK: Settling

    private func fires(_ decisions: [RatingPromptDecision]) -> [Bool] {
        var settling = RatingPromptSettling()
        return decisions.map { settling.observe($0) }
    }

    @Test func oneCalmObservationDoesNotFire() {
        #expect(fires([.request(.finishedBook)]) == [false])
    }

    @Test func twoConsecutiveCalmObservationsFireOnce() {
        let calm = RatingPromptDecision.request(.finishedBook)
        #expect(fires([calm, calm, calm]) == [false, true, false])
    }

    @Test func aBusyObservationResetsTheStreak() {
        let calm = RatingPromptDecision.request(.finishedBook)
        #expect(fires([calm, .skip(.modalPresented), calm, calm]) == [false, false, false, true])
    }

    // MARK: Store

    private func store() -> (RatingPromptStore, UserDefaults) {
        let suite = "test.ratingPrompt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (RatingPromptStore(defaults: defaults), defaults)
    }

    @Test func storePersistsRequestsAcrossInstances() {
        let (first, defaults) = store()
        first.recordRequest(version: "1.6.0", now: now)
        let reloaded = RatingPromptStore(defaults: defaults).history
        #expect(reloaded.lastRequestVersion == "1.6.0")
        #expect(reloaded.lastRequestDate == now)
    }

    @Test func noteLaunchKeepsTheFirstDate() {
        let (store, _) = store()
        store.noteLaunch(now: now)
        store.noteLaunch(now: now.addingTimeInterval(5 * day))
        #expect(store.history.firstLaunch == now)
    }

    @Test func storeRecordsFinishedBooks() {
        let (store, _) = store()
        #expect(store.history.lastFinishedBook == nil)
        store.recordFinishedBook(now: now)
        #expect(store.history.lastFinishedBook == now)
    }

    @Test func clockMovedBackAfterARequestStillStopsThePrompt() {
        let (store, _) = store()
        store.recordRequest(version: "1.5.1", now: now)
        var stored = store.history
        stored.firstLaunch = now.addingTimeInterval(-400 * day)
        stored.lastFinishedBook = now.addingTimeInterval(-30 * day - 3600)
        let earlier = now.addingTimeInterval(-30 * day)
        let decision = RatingPromptPolicy.decide(
            history: stored, listening: { quiet }, situation: calmSituation,
            appVersion: "1.6.0", now: earlier)
        #expect(decision == .skip(.requestedRecently))
    }
}
