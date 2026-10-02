import XCTest
@testable import SportsCalModel

final class TeamSeasonScheduleTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")!

    private func game(_ id: String, _ daysFromNow: Double, league: Leagues = .nba,
                      status: String? = nil, home: String = "Celtics", away: String = "Knicks",
                      score: (String, String)? = nil, season: String? = "2025-2026",
                      phase: SeasonPhase? = nil) -> Game {
        Game(idEvent: id, idLeague: "\(league.rawValue)", strHomeTeam: home, strAwayTeam: away,
             intHomeScore: score?.0, intAwayScore: score?.1, strStatus: status,
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
}
