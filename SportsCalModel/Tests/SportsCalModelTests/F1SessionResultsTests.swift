import XCTest
@testable import SportsCalModel

final class F1SessionResultsTests: XCTestCase {
    func testSprintQualiAbsoluteTimesReadAsLapTimes() {
        let entries = [
            LeaderboardEntry(name: "George Russell", score: "P1", position: 1, gap: "1:11.567"),
            LeaderboardEntry(name: "Lando Norris", score: "P2", position: 2, gap: "+1:11.608"),
            LeaderboardEntry(name: "Max Verstappen", score: "P3", position: 3),
        ]
        let gaps = RaceGap.gaps(for: entries)
        XCTAssertEqual(gaps[0], .leader)
        guard case .lapTime(let lap, let behind) = gaps[1] else { return XCTFail("expected a lap time") }
        XCTAssertEqual(lap, 71.608, accuracy: 0.0001)
        XCTAssertEqual(behind, 0.041, accuracy: 0.0001)
        XCTAssertEqual(gaps[2], .missing)
        XCTAssertEqual(RaceGap.clockString(71.608), "1:11.608")
    }

    func testRaceGapsStayGaps() {
        let entries = [
            LeaderboardEntry(name: "A", score: "P1", position: 1, gap: "1:31:44.742"),
            LeaderboardEntry(name: "B", score: "P2", position: 2, gap: "+2.341"),
            LeaderboardEntry(name: "C", score: "P3", position: 3, gap: "+1 Lap"),
            LeaderboardEntry(name: "D", score: "P4", position: 4, gap: "DNF"),
        ]
        XCTAssertEqual(RaceGap.gaps(for: entries), [.leader, .time(2.341), .laps(1), .out("DNF")])
    }

    func testJolpicaFillsMissingTeamsGapsAndQualifyingTimes() throws {
        let game = Game(idLeague: "4370", strHomeTeam: "GP", strAwayTeam: "", isoDate: nil, sessions: [
            EventSession(sessionType: "Qual", sessionName: "Qualifying", status: "post", date: "2026-10-31T21:00Z", leaderboard: [
                LeaderboardEntry(name: "Lewis Hamilton", score: "P1", position: 1, constructor: "Ferrari", gap: "1:16.514"),
            ]),
            EventSession(sessionType: "Race", sessionName: "Race", status: "post", date: "2026-11-01T20:00Z", leaderboard: [
                LeaderboardEntry(name: "Max Verstappen", score: "P1", position: 1, constructor: "Red Bull", gap: "2:20:28.772"),
                LeaderboardEntry(name: "Andrea Kimi Antonelli", score: "P8", position: 8),
            ]),
        ])
        XCTAssertEqual(game.f1RaceDay, "2026-11-01")
        let results = F1RoundResults(round: 21, raceDate: "2026-11-01", qualifying: [
            F1ResultRow(position: 1, driverName: "Lewis Hamilton", constructor: "Ferrari", qualifyingTimes: ["1:17.341", "1:16.953", "1:16.514"]),
        ], race: [
            F1ResultRow(position: 1, driverName: "Max Verstappen", constructor: "Red Bull", gap: "2:20:28.772"),
            F1ResultRow(position: 8, driverName: "Kimi Antonelli", constructor: "Mercedes", gap: "+41.002"),
        ])
        let sessions = try XCTUnwrap(game.sessionsFilled(with: results))
        XCTAssertEqual(sessions[0].leaderboard[0].qualifyingTimes?.count, 3)
        let p8 = sessions[1].leaderboard[1]
        XCTAssertEqual(p8.constructor, "Mercedes")
        XCTAssertEqual(p8.gap, "+41.002")
        // ESPN's own values are never replaced.
        XCTAssertEqual(sessions[1].leaderboard[0].gap, "2:20:28.772")
        // Nothing new: no copy.
        XCTAssertNil(game.updated(sessions: sessions).sessionsFilled(with: results))
    }

    func testLiveTickKeepsEnrichmentAndRaceDistance() {
        let stale = [EventSession(sessionType: "Race", sessionName: "Race", status: "in", progress: "Lap 22/57", leaderboard: [
            LeaderboardEntry(name: "A", score: "P1", position: 1, constructor: "McLaren"),
        ], raceState: RaceState(lap: 22, totalLaps: 57, flag: .none))]
        let fresh = [EventSession(sessionType: "Race", sessionName: "Race", status: "in", progress: "Lap 23", leaderboard: [
            LeaderboardEntry(name: "A", score: "P1", position: 1),
        ], raceState: RaceState(lap: 23, totalLaps: 0, flag: .none))]
        let merged = fresh.carryingEnrichment(from: stale)
        XCTAssertEqual(merged[0].leaderboard[0].constructor, "McLaren")
        XCTAssertEqual(merged[0].raceState?.totalLaps, 57)
        XCTAssertEqual(merged[0].progress, "Lap 23/57")
    }

    func testQualifyingCutLines() {
        XCTAssertEqual(F1RoundResults.qualifyingCutLines(fieldSize: 22).q1, 16)
        XCTAssertEqual(F1RoundResults.qualifyingCutLines(fieldSize: 20).q1, 15)
    }
}
