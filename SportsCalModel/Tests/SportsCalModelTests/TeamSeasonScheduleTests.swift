import XCTest
@testable import SportsCalModel

final class TeamSeasonScheduleTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")!

    private func game(_ id: String, _ daysFromNow: Double, league: Leagues = .nba,
                      status: String? = nil, home: String = "Celtics", away: String = "Knicks",
                      score: (String, String)? = nil, season: String? = "2025-2026",
                      phase: SeasonPhase? = nil, progress: String? = nil) -> Game {
        Game(idEvent: id, idLeague: "\(league.rawValue)", strHomeTeam: home, strAwayTeam: away,
             intHomeScore: score?.0, intAwayScore: score?.1, strStatus: status, strProgress: progress,
             isoDate: now.addingTimeInterval(daysFromNow * 86_400),
             season: season, seasonPhase: phase)
    }

    func testGroupsBySeasonThenPhaseInDateOrder() {
        let games = [
            game("po1", 100, phase: .postseason),
            game("reg2", 3, status: "NS"),
            game("pre1", -100, status: "FT", score: ("100", "90"), phase: .preseason),
            game("reg1", -2, status: "FT", score: ("101", "99")),
            game("old", -300, status: "FT", score: ("1", "2"), season: "2024-2025"),
        ]
        let schedule = TeamSeasonSchedule(games: games, now: now)

        XCTAssertEqual(schedule.seasons.map(\.season), ["2024-2025", "2025-2026"])
        let current = schedule.seasons[1]
        XCTAssertEqual(current.phases.map(\.phase), [.preseason, .regular, .postseason])
        XCTAssertEqual(current.phases[1].games.map(\.idEvent), ["reg1", "reg2"])
        XCTAssertEqual(current.displayName, "2025–26 Season")
    }

    func testAnchorsOnNextGameMidSeason() {
        let games = [
            game("a", -3, status: "FT", score: ("1", "0")),
            game("b", -1, status: "FT", score: ("1", "0")),
            game("c", 1, status: "NS"),
            game("d", 3, status: "NS"),
        ]
        XCTAssertEqual(TeamSeasonSchedule(games: games, now: now).anchorGameID, "c")
    }

    /// TheSportsDB marks scheduled games "NS"/"pre" — which `hasDoneStatus` counts as done,
    /// so the old Upcoming/Recent split filed them as results.
    func testScheduledStatusesAreNotFinal() {
        XCTAssertFalse(game("x", 1, status: "NS").isFinalStatus)
        XCTAssertFalse(game("x", 1, status: "pre", score: ("0", "0")).isFinalStatus)
        XCTAssertTrue(game("x", -1, status: "AOT").isFinalStatus)
        XCTAssertTrue(game("x", -1, status: "post").isFinalStatus)
        XCTAssertTrue(game("x", -1, status: "Final/OT").isFinalStatus)
    }

    /// ESPN files a postponed game as state "post" with "Postponed" in the detail and
    /// 0–0 scores; TheSportsDB uses PST/CANC/ABD in `strStatus`. Neither is a final.
    func testCalledOffGamesAreNeitherFinalNorResults() {
        let espnPostponed = game("x", -1, status: "post", score: ("0", "0"), progress: "Postponed")
        XCTAssertFalse(espnPostponed.isFinalStatus)
        XCTAssertEqual(espnPostponed.calledOffKind, .postponed)
        XCTAssertEqual(game("x", -1, status: "post", progress: "Canceled").calledOffKind, .cancelled)
        XCTAssertEqual(game("x", -1, status: "PST").calledOffKind, .postponed)
        XCTAssertEqual(game("x", -1, status: "ABD").calledOffKind, .abandoned)
        XCTAssertNil(game("x", -1, status: "post", progress: "Final").calledOffKind)

        let games = [
            game("w", -3, status: "FT", score: ("100", "90")),
            espnPostponed,
            game("n", 2, status: "NS"),
        ]
        let schedule = TeamSeasonSchedule(games: games, now: now)
        XCTAssertEqual(schedule.seasons.last?.phases.first?.record(forTeamID: nil, teamNames: ["Celtics"]), "1–0",
                       "a postponed 0–0 must not count as a tie")
    }

    func testAnchorsOnLiveGame() {
        let games = [
            game("a", -1, status: "FT", score: ("1", "0")),
            game("live", -0.05, status: "Q3", score: ("50", "48")),
            game("c", 2, status: "NS"),
        ]
        XCTAssertEqual(TeamSeasonSchedule(games: games, now: now).anchorGameID, "live")
    }

    func testAnchorSkipsStaleAndCalledOffGames() {
        let games = [
            game("stuck", -2, status: "2H"),
            game("postponed", 0.5, status: "PST"),
            game("next", 1, status: "NS"),
        ]
        XCTAssertEqual(TeamSeasonSchedule(games: games, now: now).anchorGameID, "next")
    }

    func testAnchorsOnLastResultInOffseason() {
        let games = [
            game("a", -40, status: "FT", score: ("1", "0")),
            game("last", -30, status: "FT", score: ("1", "0")),
        ]
        XCTAssertEqual(TeamSeasonSchedule(games: games, now: now).anchorGameID, "last")
    }

    func testLeaguesWithoutPhasesAreOneList() {
        let games = [
            game("s1", -1, league: .English_Premier_League, status: "FT", score: ("1", "1"), phase: .postseason),
            game("s2", 2, league: .English_Premier_League, status: "NS"),
        ]
        let schedule = TeamSeasonSchedule(games: games, now: now)
        XCTAssertEqual(schedule.seasons.count, 1)
        XCTAssertEqual(schedule.seasons[0].phases.count, 1)
        XCTAssertNil(schedule.seasons[0].phases[0].phase)
    }

    func testDeduplicatesById() {
        let games = [game("a", 1, status: "NS"), game("a", 1, status: "NS")]
        XCTAssertEqual(TeamSeasonSchedule(games: games, now: now).seasons[0].phases[0].games.count, 1)
    }

    func testRecordCountsOnlyFinals() {
        let games = [
            game("w", -3, status: "FT", score: ("110", "100")),              // Celtics home win
            game("l", -2, status: "FT", home: "Knicks", away: "Celtics", score: ("120", "100")),
            game("t", -1, status: "FT", score: ("3", "3")),
            game("pre", 1, status: "pre", score: ("0", "0")),               // not played yet
        ]
        let group = TeamSeasonSchedule(games: games, now: now).seasons[0].phases[0]
        XCTAssertEqual(group.record(forTeamID: nil, teamNames: ["Celtics"]), "1–1–1")
    }

    /// NHL standings count overtime and shootout losses apart (W–L–OTL); counting them
    /// as plain losses turned a 30–15–5 team into 30–20.
    func testNHLRecordCountsOvertimeAndShootoutLossesAsOTL() {
        let games = [
            game("w", -6, league: .nhl, status: "FT", score: ("4", "2")),
            game("l", -5, league: .nhl, status: "FT", score: ("1", "3")),
            game("ot", -4, league: .nhl, status: "AOT", score: ("2", "3")),
            game("so", -3, league: .nhl, status: "post", score: ("3", "4"), progress: "Final/SO"),
            game("otWin", -2, league: .nhl, status: "post", score: ("5", "4"), progress: "Final/OT"),
        ]
        let group = TeamSeasonSchedule(games: games, now: now).seasons[0].phases[0]
        XCTAssertEqual(group.record(forTeamID: nil, teamNames: ["Celtics"]), "2–1–2")
        // A team with no OT losses still reads three columns.
        let plain = TeamSeasonSchedule(games: [games[0]], now: now).seasons[0].phases[0]
        XCTAssertEqual(plain.record(forTeamID: nil, teamNames: ["Celtics"]), "1–0–0")
    }

    func testEndedPastRegulationFallsBackToPeriodCount() {
        var overtime = game("x", -1, league: .nhl, status: "post", score: ("2", "3"))
        XCTAssertFalse(overtime.endedPastRegulation)
        overtime = Game(idEvent: "x", idLeague: "\(Leagues.nhl.rawValue)", strHomeTeam: "A", strAwayTeam: "B",
                        intHomeScore: "2", intAwayScore: "3", strStatus: "post",
                        homeLinescores: [1, 1, 0, 0], awayLinescores: [1, 0, 1, 1], isoDate: now)
        XCTAssertTrue(overtime.endedPastRegulation)
    }
}
