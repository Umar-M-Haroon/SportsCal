//
//  WatchGameLogicTests.swift
//  SportsCalWatch Watch AppTests
//
//  Merge / filter / backoff rules behind WatchViewModel.
//

import Foundation
import Testing
@testable import SportsCalWatch_Watch_App
import SportsCalModel

@MainActor
struct WatchGameLogicTests {

    private func game(
        id: String?,
        league: Leagues = .nba,
        home: String = "Lakers",
        away: String = "Celtics",
        homeScore: String? = nil,
        awayScore: String? = nil,
        status: String? = nil,
        progress: String? = nil,
        tournament: String? = nil,
        timestamp: String = "2026-10-04T23:00:00Z"
    ) -> Game {
        Game(
            idEvent: id,
            idLeague: String(league.rawValue),
            strHomeTeam: home,
            strAwayTeam: away,
            intHomeScore: homeScore,
            intAwayScore: awayScore,
            strStatus: status,
            strProgress: progress,
            strTimestamp: timestamp,
            isoDate: ISO8601DateFormatter().date(from: timestamp),
            tournamentName: tournament
        )
    }

    // MARK: - mergeLive

    @Test func mergeOverlaysLiveFieldsAndKeepsScheduleOnlyFields() {
        let scheduled = game(id: "1", tournament: "Scheduled Cup", timestamp: "2026-10-04T23:00:00Z")
        let live = game(id: "1", homeScore: "50", awayScore: "48", status: "in", progress: "Q3",
                        tournament: nil, timestamp: "2026-10-05T01:00:00Z")

        let merged = WatchGameLogic.mergeLive([live], into: [scheduled])

        #expect(merged.count == 1)
        #expect(merged[0].intHomeScore == "50")
        #expect(merged[0].intAwayScore == "48")
        #expect(merged[0].strStatus == "in")
        #expect(merged[0].strProgress == "Q3")
        #expect(merged[0].tournamentName == "Scheduled Cup")
        #expect(merged[0].strTimestamp == "2026-10-04T23:00:00Z")
    }

    @Test func mergeIgnoresUnmatchedAndPreGameLiveEntries() {
        let a = game(id: "a")
        let b = game(id: "b", home: "Knicks", away: "Nets")
        let liveUnmatched = game(id: "zzz", homeScore: "1", awayScore: "0", status: "in")
        let livePre = game(id: "b", home: "Knicks", away: "Nets", homeScore: "0", awayScore: "0", status: "pre")

        let merged = WatchGameLogic.mergeLive([liveUnmatched, livePre], into: [a, b])

        #expect(merged.count == 2)
        #expect(merged.map(\.idEvent) == ["a", "b"])
        #expect(merged[1].intHomeScore == nil)
    }

    @Test func mergeDoesNotFallBackToTeamsWhenScheduledHasEventID() {
        // Same matchup, different event (e.g. tomorrow's rematch) must not take today's score.
        let scheduled = game(id: "tomorrow")
        let live = game(id: "today", homeScore: "3", awayScore: "2", status: "in")
        let merged = WatchGameLogic.mergeLive([live], into: [scheduled])
        #expect(merged[0].intHomeScore == nil)
    }

    @Test func mergeMatchesByTeamsWhenScheduledHasNoEventID() {
        let scheduled = game(id: nil)
        let live = game(id: nil, homeScore: "7", awayScore: "3", status: "in")
        let merged = WatchGameLogic.mergeLive([live], into: [scheduled])
        #expect(merged[0].intHomeScore == "7")
    }

    // MARK: - visibleGames

    @Test func visibleGamesDropsDisabledSports() {
        let nba = game(id: "1", league: .nba)
        let nhl = game(id: "2", league: .nhl)
        let visible = WatchGameLogic.visibleGames(
            [nba, nhl], enabledSports: [.basketball], hiddenCompetitions: []
        )
        #expect(visible.map(\.idEvent) == ["1"])
    }

    @Test func visibleGamesDropsHiddenCompetitions() {
        let nba = game(id: "1", league: .nba)
        let nhl = game(id: "2", league: .nhl)
        let visible = WatchGameLogic.visibleGames(
            [nba, nhl],
            enabledSports: [.basketball, .hockey],
            hiddenCompetitions: [Leagues.nhl.leagueName]
        )
        #expect(visible.map(\.idEvent) == ["1"])
    }

    // MARK: - isLive / pollInterval

    @Test func isLiveRequiresInProgressStatusAndScores() {
        #expect(WatchGameLogic.isLive(game(id: "1", homeScore: "1", awayScore: "0", status: "in")))
        #expect(!WatchGameLogic.isLive(game(id: "1", homeScore: "1", awayScore: "0", status: "FT")))
        #expect(!WatchGameLogic.isLive(game(id: "1", status: "in")))
        #expect(!WatchGameLogic.isLive(game(id: "1")))
    }

    @Test func pollIntervalBacksOffOnFailureAndCaps() {
        #expect(WatchGameLogic.pollInterval(hasLiveGames: true, consecutiveFailures: 0) == 30)
        #expect(WatchGameLogic.pollInterval(hasLiveGames: false, consecutiveFailures: 0) == 60)
        #expect(WatchGameLogic.pollInterval(hasLiveGames: true, consecutiveFailures: 2) == 120)
        #expect(WatchGameLogic.pollInterval(hasLiveGames: false, consecutiveFailures: 10) == 300)
    }
}
