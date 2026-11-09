import XCTest
@testable import SportsCalModel

final class GolfAlertDetectorTests: XCTestCase {
    private let followed: Set<String> = ["Scottie Scheffler"]

    private func row(_ name: String, _ score: String, _ position: Int, rounds: [String] = [],
                     thru: String? = nil, today: String? = nil) -> LeaderboardEntry {
        LeaderboardEntry(name: name, score: score, position: position, thruHole: thru, rounds: rounds, today: today)
    }

    private func tournament(_ rows: [LeaderboardEntry], progress: String = "Round 2 - In Progress",
                            completed: Bool = false) -> Game {
        Game(idEvent: "401", idLeague: "\(Leagues.pga.rawValue)", strHomeTeam: "The RSM Classic", strAwayTeam: "",
             strStatus: completed ? "post" : "in", strProgress: progress, isCompleted: completed,
             isoDate: nil, leaderboardEntries: rows)
    }

    func testFirstLookAnnouncesNothing() {
        let game = tournament([row("Scottie Scheffler", "-8", 1, rounds: ["66"], thru: "2", today: "-2")])
        let (alerts, state) = GolfAlertDetector.detect(game, players: followed, previous: nil)
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertEqual(state.players["Scottie Scheffler"]?.startedRounds, [2])
        XCTAssertEqual(state.players["Scottie Scheffler"]?.ledRounds, [2])
    }

    func testTeeOffLeadAndFinish() {
        let before = tournament([
            row("Ludvig Aberg", "-7", 1, rounds: ["65"], thru: "F", today: "-7"),
            row("Scottie Scheffler", "-6", 2, rounds: ["66"]),
        ], progress: "Round 1 - Complete")
        var (alerts, state) = GolfAlertDetector.detect(before, players: followed, previous: nil)
        XCTAssertTrue(alerts.isEmpty)

        let teeOff = tournament([
            row("Ludvig Aberg", "-7", 1, rounds: ["65"]),
            row("Scottie Scheffler", "-6", 2, rounds: ["66"], thru: "1", today: "E"),
        ])
        (alerts, state) = GolfAlertDetector.detect(teeOff, players: followed, previous: state)
        XCTAssertEqual(alerts.map(\.kind), [.teeOff])
        XCTAssertEqual(alerts.first?.title, "⛳️ Scottie Scheffler tees off")

        let leading = tournament([
            row("Scottie Scheffler", "-9", 1, rounds: ["66"], thru: "8", today: "-3"),
            row("Ludvig Aberg", "-7", 2, rounds: ["65"]),
        ])
        (alerts, state) = GolfAlertDetector.detect(leading, players: followed, previous: state)
        XCTAssertEqual(alerts.map(\.kind), [.lead])
        // Same round, still leading: once is enough.
        (alerts, state) = GolfAlertDetector.detect(leading, players: followed, previous: state)
        XCTAssertTrue(alerts.isEmpty)

        let finished = tournament([
            row("Scottie Scheffler", "-12", 1, rounds: ["66", "64"], thru: "F", today: "-6"),
            row("Ludvig Aberg", "-7", 2, rounds: ["65"]),
        ])
        (alerts, state) = GolfAlertDetector.detect(finished, players: followed, previous: state)
        XCTAssertEqual(alerts.map(\.kind), [.finish])
        XCTAssertEqual(alerts.first?.title, "Scottie Scheffler finishes round 2 at −12")
        XCTAssertEqual(alerts.first?.body, "−6 today · 1 · The RSM Classic")
    }

    func testFirstSeenMidRoundIsNotATeeOff() {
        let start = tournament([row("Scottie Scheffler", "-6", 2, rounds: ["66"])], progress: "Round 1 - Complete")
        let (_, state) = GolfAlertDetector.detect(start, players: followed, previous: nil)
        let midRound = tournament([row("Scottie Scheffler", "-6", 3, rounds: ["66"], thru: "11", today: "E")])
        XCTAssertTrue(GolfAlertDetector.detect(midRound, players: followed, previous: state).alerts.isEmpty)
    }

    func testWinIsAnnouncedOnce() {
        let live = tournament([row("Scottie Scheffler", "-20", 1, rounds: ["66", "64", "65"], thru: "17", today: "-4")],
                              progress: "Round 4 - In Progress")
        var (_, state) = GolfAlertDetector.detect(live, players: followed, previous: nil)
        let final = tournament([row("Scottie Scheffler", "-21", 1, rounds: ["66", "64", "65", "64"], thru: "F", today: "-5")],
                               progress: "Final", completed: true)
        var alerts: [GolfAlert]
        (alerts, state) = GolfAlertDetector.detect(final, players: followed, previous: state)
        XCTAssertEqual(alerts.map(\.title), ["Scottie Scheffler finishes round 4 at −21", "🏆 Scottie Scheffler wins"])
        XCTAssertTrue(GolfAlertDetector.detect(final, players: followed, previous: state).alerts.isEmpty)
    }
}
