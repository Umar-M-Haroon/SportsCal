//
//  SoccerPresentationTests.swift
//  SportsCalModelTests
//
//  Home-first order, shootout winners, aggregates, row scorer lines and the match
//  centre timeline.
//

import XCTest
@testable import SportsCalModel

final class SoccerPresentationTests: XCTestCase {
    private func soccerGame(home: String = "1", away: String = "1", extras: ScoreboardExtras? = nil,
                            aggregateScore: String? = nil, progress: String? = nil) -> Game {
        Game(idLeague: "\(Leagues.English_League_Championship.rawValue)", strHomeTeam: "Liverpool", strAwayTeam: "Chelsea",
             intHomeScore: home, intAwayScore: away, strStatus: "post", strProgress: progress,
             isoDate: nil, aggregateScore: aggregateScore, scoreboardExtras: extras)
    }

    func testOrderAndMatchupTitle() {
        let soccer = soccerGame()
        XCTAssertTrue(soccer.displaysHomeFirst)
        XCTAssertEqual(soccer.matchupTitle, "Liverpool vs Chelsea")
        XCTAssertEqual(soccer.displayOrdered(home: "H", away: "A").first, "H")

        let nba = Game(idLeague: "\(Leagues.nba.rawValue)", strHomeTeam: "Lakers", strAwayTeam: "Celtics", isoDate: nil)
        XCTAssertFalse(nba.displaysHomeFirst)
        XCTAssertEqual(nba.matchupTitle, "Celtics @ Lakers")
        XCTAssertEqual(nba.displayOrdered(home: "H", away: "A").first, "A")
    }

    func testShootoutDecidesTheWinner() {
        let game = soccerGame(extras: ScoreboardExtras(homeWinner: true, awayWinner: false,
                                                       homeShootoutScore: 6, awayShootoutScore: 5))
        XCTAssertEqual(game.winningSide, .home)
        XCTAssertEqual(game.shootoutLine, "6–5 pens")
        XCTAssertEqual(game.soccerDecisionSpoken(homeName: "Liverpool", awayName: "Chelsea"),
                       "Liverpool won 6–5 on penalties")
        XCTAssertNil(soccerGame().winningSide)
        XCTAssertEqual(soccerGame(home: "2", away: "1").winningSide, .home)
    }

    func testAggregatePrefersStructuredAndFlipsTheOldText() {
        let structured = soccerGame(extras: ScoreboardExtras(homeAggregate: 3, awayAggregate: 2), aggregateScore: "Agg: 2-3")
        XCTAssertEqual(structured.aggregateLine, "Agg 3–2")
        // Old servers: "Agg: away-home".
        XCTAssertEqual(soccerGame(aggregateScore: "Agg: 1-4").aggregateGoals, SoccerScore(home: 4, away: 1))
        // Not soccer → no aggregate (WNBA series wins were read as one).
        let wnba = Game(idLeague: "\(Leagues.wnba.rawValue)", strHomeTeam: "A", strAwayTeam: "B", isoDate: nil, aggregateScore: "Agg: 2-1")
        XCTAssertNil(wnba.aggregateLine)
    }

    func testScorerLineAndRedCards() {
        let details: [MatchIncident] = [
            MatchIncident(kind: .goal, clock: "12'", athlete: "Bukayo Saka", side: .home),
            MatchIncident(kind: .redCard, clock: "30'", athlete: "Moisés Caicedo", side: .away),
            MatchIncident(kind: .penaltyGoal, clock: "45'+2'", athlete: "Alexis Mac Allister", side: .home),
            MatchIncident(kind: .goal, clock: "67'", athlete: "Bukayo Saka", side: .home),
            MatchIncident(kind: .ownGoal, clock: "80'", athlete: "Virgil van Dijk", side: .away),
        ]
        let game = soccerGame(home: "3", away: "1", extras: ScoreboardExtras(soccerDetails: details))
        XCTAssertEqual(game.scorerLine(.home), "Saka 12', 67' · Mac Allister 45'+2' (P)")
        XCTAssertEqual(game.scorerLine(.away), "van Dijk 80' (OG)")
        XCTAssertEqual(game.redCards(.away), 1)
        XCTAssertEqual(game.redCards(.home), 0)

        // The Live Activity's extras carry the latest goal's side, so it sits under
        // the team it counted for.
        let activity = LiveActivitySoccer(game: game)
        XCTAssertEqual(activity?.lastGoal, "van Dijk 80' (OG)")
        XCTAssertEqual(activity?.lastGoalSide, .away)
        XCTAssertEqual(activity?.awayRedCards, 1)
        XCTAssertNil(activity?.homeRedCards)
    }

    func testSoccerRoundRidesTheWireAsTheMatchday() throws {
        let game = Game(idLeague: "\(Leagues.English_Premier_League.rawValue)", strHomeTeam: "A", strAwayTeam: "B",
                        isoDate: nil, sportsDBRound: 12)
        let decoded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(decoded.soccerMatchday, 12)
        let cup = Game(idLeague: "\(Leagues.FA_Cup.rawValue)", strHomeTeam: "A", strAwayTeam: "B", isoDate: nil, sportsDBRound: 3)
        XCTAssertNil(cup.soccerMatchday)
    }

    func testClockPeriod() {
        XCTAssertEqual(soccerGame(progress: "45'+2'").soccerClockPeriod, 1)
        XCTAssertEqual(soccerGame(progress: "HT").soccerClockPeriod, 2)
        XCTAssertEqual(soccerGame(progress: "90'+4'").soccerClockPeriod, 2)
        XCTAssertEqual(soccerGame(progress: "98'").soccerClockPeriod, 3)
    }

    // MARK: Timeline

    private func event(_ id: String, _ type: SoccerMatchEventType, period: Int, side: BracketSide) -> SoccerMatchEvent {
        SoccerMatchEvent(id: id, type: type, typeText: type.rawValue, clock: nil, period: period, side: side)
    }

    func testTimelineDividersAndRunningScore() {
        let events = [
            event("g1", .goal, period: 1, side: .home),
            event("y1", .yellowCard, period: 1, side: .away),
            event("g2", .ownGoal, period: 2, side: .away),
            event("g3", .goal, period: 2, side: .home),
        ]
        let rows = SoccerTimeline.rows(events: events, finalScore: SoccerScore(home: 2, away: 1), isFinished: true)
        XCTAssertEqual(rows.map(\.id), ["e-g1", "e-y1", "d-HT", "e-g2", "e-g3", "d-FT"])
        XCTAssertEqual(rows[0], .event(events[0], score: SoccerScore(home: 1, away: 0)))
        XCTAssertEqual(rows[2], .divider(label: "HT", score: SoccerScore(home: 1, away: 0)))
        XCTAssertEqual(rows[4], .event(events[3], score: SoccerScore(home: 2, away: 1)))
    }

    func testTimelineDropsARunningScoreThatDoesNotAddUp() {
        let rows = SoccerTimeline.rows(events: [event("g1", .goal, period: 1, side: .home)],
                                       finalScore: SoccerScore(home: 2, away: 0), isFinished: true)
        XCTAssertEqual(rows.first, .event(event("g1", .goal, period: 1, side: .home), score: nil))
        XCTAssertEqual(rows.last, .divider(label: "FT", score: SoccerScore(home: 2, away: 0)))
    }

    func testTimelineShowsHalfTimeBeforeTheSecondHalfHasEvents() {
        let rows = SoccerTimeline.rows(events: [event("g1", .goal, period: 1, side: .away)],
                                       finalScore: SoccerScore(home: 0, away: 1), isFinished: false, currentPeriod: 2)
        XCTAssertEqual(rows.map(\.id), ["e-g1", "d-HT"])
    }

    func testShootoutIsGroupedFromTheScoreboard() {
        let details: [MatchIncident] = [
            MatchIncident(kind: .penaltyGoal, clock: "40'", athlete: "Morgan Rogers", side: .away),
            MatchIncident(kind: .shootoutGoal, clock: "91'", athlete: "Alexis Mac Allister", side: .home),
            MatchIncident(kind: .shootoutMiss, clock: "92'", athlete: "Pedro Neto", side: .away),
        ]
        let rows = SoccerTimeline.rows(events: [event("p1", .penaltyGoal, period: 1, side: .away),
                                                event("p2", .penaltyGoal, period: 1, side: .home)],
                                       shootoutDetails: details,
                                       finalScore: SoccerScore(home: 1, away: 1), isFinished: true)
        XCTAssertEqual(rows.map(\.id), ["e-p1", "e-p2", "d-HT", "d-FT", "pens", "k-1-Alexis Mac Allister", "k-2-Pedro Neto"])
        XCTAssertEqual(rows[rows.count - 3], .shootoutHeader(score: SoccerScore(home: 1, away: 0)))
        guard case .shootoutKick(let last, let tally) = rows[rows.count - 1] else { return XCTFail("no kick") }
        XCTAssertFalse(last.scored)
        XCTAssertEqual(tally, SoccerScore(home: 1, away: 0))
    }
}
