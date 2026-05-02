#if canImport(ActivityKit) && os(iOS)
import XCTest
import ActivityKit
import SportsCalModel
@testable import Scoreline

/// Pins the WebSocket → LiveActivity matching logic. A regression here means
/// the user's iPhone Lock Screen quietly stops mirroring the score even though
/// the server-side push pipeline is still working — silent and confusing. So
/// pin both the eventID-first precedence and the team-name fallback.
final class LiveActivityMatcherTests: XCTestCase {

    private func game(
        eventID: String? = nil,
        home: String,
        away: String,
        homeScore: Int = 0,
        awayScore: Int = 0,
        status: String = "in",
        progress: String? = nil
    ) -> Game {
        Game(
            idLiveScore: nil,
            idEvent: eventID,
            strSport: nil,
            idLeague: nil,
            strLeague: nil,
            idHomeTeam: nil,
            idAwayTeam: nil,
            strHomeTeam: home,
            strAwayTeam: away,
            strHomeTeamBadge: nil,
            strAwayTeamBadge: nil,
            intHomeScore: String(homeScore),
            intAwayScore: String(awayScore),
            strPlayer: nil,
            idPlayer: nil,
            intEventScore: nil,
            intEventScoreTotal: nil,
            strStatus: status,
            strProgress: progress,
            strEventTime: nil,
            dateEvent: nil,
            updated: nil,
            strTimestamp: nil,
            lastPlay: nil,
            homeLinescores: nil,
            awayLinescores: nil,
            homeLeaders: nil,
            awayLeaders: nil,
            isCompleted: false,
            isoDate: Date(),
            leaderboardEntries: nil,
            sessions: nil,
            venueName: nil,
            homeTeamColor: nil,
            awayTeamColor: nil,
            homeRecord: nil,
            awayRecord: nil,
            circuitInfo: nil,
            golfCourseInfo: nil,
            legDisplay: nil,
            aggregateScore: nil,
            homeSeed: nil,
            awaySeed: nil,
            tournamentName: nil,
            homeInjuries: nil,
            awayInjuries: nil,
            raceTiming: nil,
            playoff: nil,
            lastPlayScoreboardID: nil
        )
    }

    // MARK: - buildLookup

    func test_buildLookup_indexesBothByEventIDAndTeams() {
        let lookup = LiveActivityMatcher.buildLookup(from: [
            game(eventID: "e1", home: "Lakers", away: "Warriors", homeScore: 14)
        ])
        XCTAssertEqual(lookup.byEventID["e1"]?.homeScore, 14)
        XCTAssertEqual(lookup.byTeams["lakers|warriors"]?.homeScore, 14)
    }

    func test_buildLookup_skipsEventIDIndex_whenNil_butKeepsTeamIndex() {
        // TheSportsDB sometimes returns events without IDs. The team-name
        // fallback must still work in that case.
        let lookup = LiveActivityMatcher.buildLookup(from: [
            game(eventID: nil, home: "Lakers", away: "Warriors", homeScore: 7)
        ])
        XCTAssertTrue(lookup.byEventID.isEmpty)
        XCTAssertEqual(lookup.byTeams["lakers|warriors"]?.homeScore, 7)
    }

    func test_buildLookup_lowercasesTeamKeys() {
        let lookup = LiveActivityMatcher.buildLookup(from: [
            game(eventID: "e1", home: "LAKERS", away: "Warriors")
        ])
        XCTAssertNotNil(lookup.byTeams["lakers|warriors"])
        XCTAssertNil(lookup.byTeams["LAKERS|Warriors"])
    }

    // MARK: - matchedState

    func test_matchedState_eventIDTakesPrecedence() {
        // If both indexes match, eventID wins — even when the team-key entry
        // points at a different game (which can happen mid-update if two games
        // share team names like NFL/MLB Giants).
        let preferred = LiveSportActivityAttributes.ContentState(homeScore: 99, awayScore: 1, status: "in", progress: nil, lastPlay: nil)
        let other = LiveSportActivityAttributes.ContentState(homeScore: 0, awayScore: 0, status: "pre", progress: nil, lastPlay: nil)
        let lookup = LiveActivityMatcher.StateLookup(
            byEventID: ["e1": preferred],
            byTeams: ["lakers|warriors": other]
        )
        let resolved = LiveActivityMatcher.matchedState(eventID: "e1", homeTeam: "Lakers", awayTeam: "Warriors", in: lookup)
        XCTAssertEqual(resolved, preferred)
    }

    func test_matchedState_fallsBackToTeamKey_whenEventIDMissing() {
        let teamState = LiveSportActivityAttributes.ContentState(homeScore: 7, awayScore: 3, status: "in", progress: nil, lastPlay: nil)
        let lookup = LiveActivityMatcher.StateLookup(
            byEventID: [:],
            byTeams: ["lakers|warriors": teamState]
        )
        let resolved = LiveActivityMatcher.matchedState(eventID: "missing-id", homeTeam: "Lakers", awayTeam: "Warriors", in: lookup)
        XCTAssertEqual(resolved, teamState)
    }

    func test_matchedState_caseInsensitiveTeams() {
        let teamState = LiveSportActivityAttributes.ContentState(homeScore: 7, awayScore: 3, status: "in", progress: nil, lastPlay: nil)
        let lookup = LiveActivityMatcher.StateLookup(byEventID: [:], byTeams: ["lakers|warriors": teamState])
        let resolved = LiveActivityMatcher.matchedState(eventID: "x", homeTeam: "LAKERS", awayTeam: "warriors", in: lookup)
        XCTAssertEqual(resolved, teamState)
    }

    func test_matchedState_homeAwayOrderMatters() {
        // A "Lakers @ Warriors" activity must NOT match a "Warriors @ Lakers" game.
        let lookup = LiveActivityMatcher.StateLookup(byEventID: [:], byTeams: ["warriors|lakers": .init(homeScore: 1, awayScore: 0, status: "in", progress: nil, lastPlay: nil)])
        XCTAssertNil(LiveActivityMatcher.matchedState(eventID: "x", homeTeam: "Lakers", awayTeam: "Warriors", in: lookup))
    }

    func test_matchedState_returnsNil_whenNeitherIndexMatches() {
        let lookup = LiveActivityMatcher.StateLookup(byEventID: [:], byTeams: [:])
        XCTAssertNil(LiveActivityMatcher.matchedState(eventID: "x", homeTeam: "Lakers", awayTeam: "Warriors", in: lookup))
    }

    // MARK: - resolveUpdate (the actual decision point)

    func test_resolveUpdate_returnsNil_whenStateIsUnchanged() {
        let same = LiveSportActivityAttributes.ContentState(homeScore: 7, awayScore: 3, status: "in", progress: "1Q", lastPlay: nil)
        let lookup = LiveActivityMatcher.StateLookup(byEventID: ["e1": same], byTeams: [:])
        let result = LiveActivityMatcher.resolveUpdate(
            eventID: "e1", homeTeam: "Lakers", awayTeam: "Warriors",
            currentState: same, in: lookup
        )
        XCTAssertNil(result, "Identical state must not trigger a redundant update")
    }

    func test_resolveUpdate_returnsNewState_whenScoreChanged() {
        let current = LiveSportActivityAttributes.ContentState(homeScore: 7, awayScore: 3, status: "in", progress: "1Q", lastPlay: nil)
        let updated = LiveSportActivityAttributes.ContentState(homeScore: 10, awayScore: 3, status: "in", progress: "1Q", lastPlay: nil)
        let lookup = LiveActivityMatcher.StateLookup(byEventID: ["e1": updated], byTeams: [:])
        let result = LiveActivityMatcher.resolveUpdate(
            eventID: "e1", homeTeam: "Lakers", awayTeam: "Warriors",
            currentState: current, in: lookup
        )
        XCTAssertEqual(result, updated)
    }

    func test_resolveUpdate_returnsNil_whenNoMatch() {
        let current = LiveSportActivityAttributes.ContentState(homeScore: 0, awayScore: 0, status: "pre", progress: nil, lastPlay: nil)
        let lookup = LiveActivityMatcher.StateLookup(byEventID: [:], byTeams: [:])
        XCTAssertNil(LiveActivityMatcher.resolveUpdate(
            eventID: "missing", homeTeam: "Knicks", awayTeam: "Celtics",
            currentState: current, in: lookup
        ))
    }

    // MARK: - End-to-end through buildLookup + resolveUpdate

    func test_endToEnd_eventIDDivergence_teamNameFallbackStillUpdates() {
        // Activity was created with TheSportsDB event ID "tsdb-1", but the live
        // WebSocket data uses ESPN event ID "espn-99" for the same game.
        // Without team-name fallback, the activity would never get updates.
        let lookup = LiveActivityMatcher.buildLookup(from: [
            game(eventID: "espn-99", home: "Lakers", away: "Warriors", homeScore: 14, awayScore: 7, status: "in")
        ])
        let current = LiveSportActivityAttributes.ContentState(homeScore: 0, awayScore: 0, status: "pre", progress: nil, lastPlay: nil)
        let result = LiveActivityMatcher.resolveUpdate(
            eventID: "tsdb-1", homeTeam: "Lakers", awayTeam: "Warriors",
            currentState: current, in: lookup
        )
        XCTAssertEqual(result?.homeScore, 14)
    }
}
#endif
