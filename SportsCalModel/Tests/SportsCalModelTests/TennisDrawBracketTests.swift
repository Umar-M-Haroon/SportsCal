import XCTest
@testable import SportsCalModel

/// The draw is rebuilt from who played whom, since ESPN sends matches in order of play.
final class TennisDrawBracketTests: XCTestCase {

    private func match(_ id: String, _ round: String, _ home: Int, _ away: Int, at hour: Int,
                       slug: String = "mens-singles") -> Game {
        Game(idEvent: id, idLeague: "\(Leagues.atp.rawValue)", idHomeTeam: "\(home)", idAwayTeam: "\(away)",
             strHomeTeam: "Player \(home)", strAwayTeam: "Player \(away)", strStatus: "post",
             strTimestamp: String(format: "2026-11-%02dT10:00Z", hour), isoDate: nil,
             tournamentName: "Paris", round: round, drawSlug: slug)
    }

    func testEarlierRoundsFollowTheMatchesTheyFed() {
        // Order of play deliberately scrambled against draw order.
        let games = [
            match("f", "Final", 1, 8, at: 9),
            match("sf2", "Semifinal", 5, 8, at: 7),
            match("sf1", "Semifinal", 1, 4, at: 8),
            match("qf4", "Quarterfinal", 7, 8, at: 3),
            match("qf2", "Quarterfinal", 4, 3, at: 1),
            match("qf3", "Quarterfinal", 6, 5, at: 2),
            match("qf1", "Quarterfinal", 2, 1, at: 4),
        ]
        let bracket = TennisDrawBracket(games: games)
        XCTAssertEqual(bracket.rounds.map(\.shortLabel), ["QF", "SF", "F"])
        XCTAssertEqual(bracket.rounds[2].slots.map { $0?.idEvent }, ["f"])
        XCTAssertEqual(bracket.rounds[1].slots.map { $0?.idEvent }, ["sf1", "sf2"])
        XCTAssertEqual(bracket.rounds[0].slots.map { $0?.idEvent }, ["qf1", "qf2", "qf3", "qf4"])
    }

    func testFirstRoundByesAreEmptySlots() {
        // Seeds 1 and 8 start in round 2.
        let games = [
            match("r2a", "Round 2", 1, 3, at: 5),
            match("r2b", "Round 2", 6, 8, at: 6),
            match("r1a", "Round 1", 2, 3, at: 1),
            match("r1b", "Round 1", 6, 7, at: 2),
        ]
        let bracket = TennisDrawBracket(games: games)
        XCTAssertEqual(bracket.rounds[0].slots.map { $0?.idEvent }, [nil, "r1a", "r1b", nil])
        XCTAssertTrue(bracket.isBye(round: 0, slot: 0))
        XCTAssertFalse(bracket.isBye(round: 0, slot: 1))
        XCTAssertTrue(bracket.isBye(round: 0, slot: 3))
    }

    func testUnlinkedMatchesGoBelowAndColumnsStayTwoToOne() {
        // Round 2 has only one match so far; three round-1 matches feed nothing yet.
        let games = [
            match("r2a", "Round 2", 1, 3, at: 5),
            match("r1a", "Round 1", 1, 2, at: 1),
            match("r1b", "Round 1", 3, 4, at: 2),
            match("r1c", "Round 1", 5, 6, at: 3),
            match("r1d", "Round 1", 7, 8, at: 4),
            match("r1e", "Round 1", 9, 10, at: 4),
        ]
        let bracket = TennisDrawBracket(games: games)
        let first = bracket.rounds[0].slots
        let second = bracket.rounds[1].slots
        XCTAssertEqual(Array(first.prefix(2)).map { $0?.idEvent }, ["r1a", "r1b"])
        XCTAssertEqual(first.compactMap { $0?.idEvent }.count, 5)
        XCTAssertEqual(first.count, second.count * 2)
        XCTAssertEqual(second.first??.idEvent, "r2a")
    }

    func testQualifyingAndGroupsAreLeftOut() {
        let games = [
            match("q", "Qualifying Final", 1, 2, at: 1),
            match("g", "Group Stage", 3, 4, at: 2),
            match("sf", "Semifinal", 3, 5, at: 3),
        ]
        XCTAssertEqual(TennisDrawBracket(games: games).rounds.map(\.name), ["Semifinal"])
    }

    func testRoundOrder() {
        let names = ["Final", "Round 2", "Quarterfinal", "Round of 16", "Round 1", "Semifinal", "Round 4"]
        let sorted = names.sorted { TennisDrawBracket.rank(ofRound: $0)! < TennisDrawBracket.rank(ofRound: $1)! }
        XCTAssertEqual(sorted, ["Round 1", "Round 2", "Round 4", "Round of 16", "Quarterfinal", "Semifinal", "Final"])
        XCTAssertNil(TennisDrawBracket.rank(ofRound: "Qualifying 1st Round"))
    }

    func testSinglesKeepsOneTourAndDropsDoubles() {
        let games = [
            match("m", "Final", 1, 2, at: 1),
            match("w", "Final", 3, 4, at: 1, slug: "womens-singles"),
            match("d", "Final", 5, 6, at: 1, slug: "mens-doubles"),
        ]
        XCTAssertEqual(TennisDrawBracket.singles(games, tour: .wta).map(\.idEvent), ["w"])
        XCTAssertEqual(TennisDrawBracket.singles(games, tour: nil).map(\.idEvent), ["m", "w"])
    }
}
