import XCTest
@testable import SportsCalModel

/// Pins tennis/golf event tiers and what each coverage setting lets through. Names are
/// real ESPN names (sponsors included), since that's what the tables must match.
final class EventTierTests: XCTestCase {

    private func tennis(_ tournament: String?, draw: String = "mens-singles", round: String? = "Round 1") -> Game {
        let league: Leagues = draw.hasPrefix("womens") ? .wta : .atp
        return Game(idEvent: "1", idLeague: "\(league.rawValue)", idHomeTeam: "h", idAwayTeam: "a",
                    strHomeTeam: "Player A", strAwayTeam: "Player B", isoDate: nil,
                    tournamentName: tournament, round: round, drawSlug: draw)
    }

    private func golf(_ name: String) -> Game {
        Game(idEvent: "1", idLeague: "\(Leagues.pga.rawValue)", strHomeTeam: name, strAwayTeam: "Leader", isoDate: nil)
    }

    // MARK: - Tiers

    func testTennisTiers() {
        XCTAssertEqual(tennis("US Open").eventTier, .major)
        XCTAssertEqual(tennis("Wimbledon").eventTier, .major)
        XCTAssertEqual(tennis("Roland Garros").eventTier, .major)
        XCTAssertEqual(tennis("BNP Paribas Open").eventTier, .premier)
        XCTAssertEqual(tennis("Miami Open presented by Itaú").eventTier, .premier)
        XCTAssertEqual(tennis("Nitto ATP Finals").eventTier, .premier)
        XCTAssertEqual(tennis("Guadalajara Open presentado por Santander", draw: "womens-singles").eventTier, .tour)
        XCTAssertEqual(tennis("Zavarovalnica Triglav Ljubljana", draw: "womens-singles").eventTier, .tour)
    }

    func testTourSpecificPremierEvents() {
        // WTA 1000, ATP 500 in the same week under the same name.
        XCTAssertEqual(tennis("China Open", draw: "womens-singles").eventTier, .premier)
        XCTAssertEqual(tennis("China Open", draw: "mens-singles").eventTier, .tour)
        // Men's-only 1000.
        XCTAssertEqual(tennis("Rolex Monte-Carlo Masters", draw: "mens-singles").eventTier, .premier)
        XCTAssertEqual(tennis("Rolex Monte-Carlo Masters", draw: "mixed-doubles").eventTier, .premier)
    }

    func testGolfTiers() {
        XCTAssertEqual(golf("Masters Tournament").eventTier, .major)
        XCTAssertEqual(golf("PGA Championship").eventTier, .major)
        XCTAssertEqual(golf("U.S. Open").eventTier, .major)
        XCTAssertEqual(golf("The Open").eventTier, .major)
        XCTAssertEqual(golf("THE PLAYERS Championship").eventTier, .premier)
        XCTAssertEqual(golf("the Memorial Tournament pres. by Workday").eventTier, .premier)
        XCTAssertEqual(golf("Biltmore Championship Asheville").eventTier, .tour)
        // The old `isMajor` matched any "the open" substring.
        XCTAssertEqual(golf("Genesis Scottish Open").eventTier, .tour)
        XCTAssertFalse(golf("Genesis Scottish Open").isMajor)
    }

    func testTeamSportsAndUnnamedTennisHaveNoTier() {
        let nba = Game(idEvent: "1", idLeague: "\(Leagues.nba.rawValue)", strHomeTeam: "A", strAwayTeam: "B", isoDate: nil)
        XCTAssertNil(nba.eventTier)
        XCTAssertNil(tennis(nil).eventTier)
    }

    // MARK: - Rounds

    func testRounds() {
        XCTAssertTrue(tennis("US Open", round: "Qualifying 1st Round").isQualifyingRound)
        XCTAssertTrue(tennis("US Open", round: "Qualifying Final").isQualifyingRound)
        XCTAssertFalse(tennis("US Open", round: "Qualifying Final").isLateRound)
        XCTAssertTrue(tennis("US Open", round: "Final").isLateRound)
        XCTAssertTrue(tennis("US Open", round: "Semifinal").isLateRound)
        XCTAssertFalse(tennis("US Open", round: "Quarterfinal").isLateRound)
        XCTAssertFalse(tennis("US Open", round: "Round of 16").isLateRound)
    }

    // MARK: - Coverage

    func testEverythingPassesAll() {
        XCTAssertTrue(tennis("Guadalajara Open", round: "Qualifying 1st Round").passesCoverage(.everything))
    }

    func testBigEvents() {
        XCTAssertTrue(tennis("US Open").passesCoverage(.bigEvents))
        XCTAssertTrue(tennis("Miami Open").passesCoverage(.bigEvents))
        XCTAssertFalse(tennis("Guadalajara Open", draw: "womens-singles").passesCoverage(.bigEvents))
        XCTAssertFalse(tennis("US Open", round: "Qualifying 1st Round").passesCoverage(.bigEvents))
        XCTAssertTrue(golf("THE PLAYERS Championship").passesCoverage(.bigEvents))
        XCTAssertFalse(golf("Biltmore Championship Asheville").passesCoverage(.bigEvents))
    }

    func testMajorsKeepsPremierLateRounds() {
        XCTAssertTrue(tennis("Wimbledon", round: "Round 1").passesCoverage(.majors))
        XCTAssertFalse(tennis("Miami Open", round: "Quarterfinal").passesCoverage(.majors))
        XCTAssertTrue(tennis("Miami Open", round: "Final").passesCoverage(.majors))
        XCTAssertFalse(tennis("Guadalajara Open", draw: "womens-singles", round: "Final").passesCoverage(.majors))
        XCTAssertFalse(golf("THE PLAYERS Championship").passesCoverage(.majors))
        XCTAssertTrue(golf("Masters Tournament").passesCoverage(.majors))
    }

    func testFavoritesAndUnclassifiedAlwaysPass() {
        XCTAssertTrue(tennis("Guadalajara Open", draw: "womens-singles").passesCoverage(.majors, isFavorite: true))
        XCTAssertTrue(tennis(nil).passesCoverage(.majors))
    }

    func testStoredCoverageDefaultsToBigEvents() {
        let defaults = UserDefaults(suiteName: "EventTierTests")!
        defaults.removePersistentDomain(forName: "EventTierTests")
        XCTAssertEqual(EventCoverage.stored(for: .tennis, in: defaults), .bigEvents)
        defaults.set("everything", forKey: "coverageTennis")
        XCTAssertEqual(EventCoverage.stored(for: .tennis, in: defaults), .everything)
        XCTAssertEqual(EventCoverage.stored(for: .golf, in: defaults), .bigEvents)
        XCTAssertEqual(EventCoverage.stored(for: .nfl, in: defaults), .everything)
    }
}

final class TournamentDigestTests: XCTestCase {

    private func match(_ id: String, _ tournament: String, home: String = "Jannik Sinner", away: String = "Carlos Alcaraz",
                       round: String = "Round 1", status: String = "pre", time: String = "2026-09-01T15:00Z",
                       sets: ([Double], [Double])? = nil) -> Game {
        Game(idEvent: id, idLeague: "\(Leagues.atp.rawValue)", idHomeTeam: "h\(id)", idAwayTeam: "a\(id)",
             strHomeTeam: home, strAwayTeam: away, strStatus: status, strTimestamp: time,
             homeLinescores: sets?.0, awayLinescores: sets?.1, isoDate: nil,
             tournamentName: tournament, round: round, drawSlug: "mens-singles")
    }

    private func nba(_ id: String) -> Game {
        Game(idEvent: id, idLeague: "\(Leagues.nba.rawValue)", strHomeTeam: "Knicks", strAwayTeam: "Celtics", isoDate: nil)
    }

    func testCollapsesEachTournamentIntoOneRowInPlace() {
        let games = [match("1", "US Open"), nba("n1"), match("2", "China Open"), match("3", "US Open")]
        let out = TournamentDigest.collapsingTennisMatches(games)
        XCTAssertEqual(out.map(\.strHomeTeam), ["US Open", "Knicks", "China Open"])
        XCTAssertEqual(out[0].strProgress, "2 matches")
        XCTAssertFalse(out[0].isTennisMatch)
        XCTAssertTrue(out[0].isIndividualSport)
        XCTAssertEqual(Set(out.map(\.id)).count, 3)
    }

    func testFeaturesLiveThenLateRoundMatches() {
        let games = [
            match("1", "US Open", round: "Round 1"),
            match("2", "US Open", home: "Novak Djokovic", away: "Ben Shelton", round: "Semifinal"),
            match("3", "US Open", home: "Taylor Fritz", away: "Jack Draper", round: "Round 1", status: "in",
                  sets: ([6, 3], [4, 2])),
        ]
        let row = TournamentDigest.collapsingTennisMatches(games)[0]
        XCTAssertEqual(row.strStatus, "in")
        XCTAssertEqual(row.strProgress, "1 live")
        XCTAssertEqual(row.leaderboardEntries?.map(\.name), ["Fritz v Draper", "Djokovic v Shelton", "Sinner v Alcaraz"])
        XCTAssertEqual(row.leaderboardEntries?.map(\.score), ["6-4 3-2", "SF", "R1"])
    }

    func testKeptMatchesStaySeparate() {
        let games = [match("1", "US Open"), match("2", "US Open", home: "Coco Gauff")]
        let out = TournamentDigest.collapsingTennisMatches(games) { $0.strHomeTeam == "Coco Gauff" }
        XCTAssertEqual(out.map(\.strHomeTeam), ["US Open", "Coco Gauff"])
        XCTAssertEqual(out[0].strProgress, "1 match")
    }
}
