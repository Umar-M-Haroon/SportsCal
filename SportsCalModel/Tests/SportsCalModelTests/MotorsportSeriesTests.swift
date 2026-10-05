import XCTest
@testable import SportsCalModel

/// NASCAR (and any racing series after it) shares the racing bucket with F1 in memory,
/// but must stay invisible to app versions that render every racing game as F1.
final class MotorsportSeriesTests: XCTestCase {
    private let f1 = Game(idEvent: "401", idLeague: "4370", strHomeTeam: "Grand Prix", strAwayTeam: "Leader", isoDate: nil)
    private let cup = Game(idEvent: "nascar-5630", idLeague: "4393", strHomeTeam: "South Point 400", strAwayTeam: "Leader", isoDate: nil)

    func testNASCARIsRacingNotSoccer() {
        XCTAssertTrue(Leagues.nascarCup.isRacing)
        XCTAssertFalse(Leagues.nascarCup.isSoccer, "isSoccer is by exclusion; a miss here files NASCAR under soccer")
        XCTAssertTrue(Leagues.nascarCup.isMotorsportSeries)
        XCTAssertFalse(Leagues.formula1.isMotorsportSeries)
        XCTAssertEqual(SportType(league: .nascarCup), .racing)
        XCTAssertTrue(Leagues.nascarCup.isHiddenByDefault)
        XCTAssertNil(Leagues.nascarCup.espnSlug, "sourced from NASCAR, so ESPN league loops must skip it")
        XCTAssertTrue(cup.isRace)
        XCTAssertTrue(cup.isNASCAR)
        XCTAssertFalse(f1.isNASCAR)
    }

    func testOtherSeriesTravelUnderTheirOwnKey() throws {
        let score = LiveScore(racing: LiveEvent(events: [f1, cup]))
        let data = try JSONEncoder().encode(score)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // What an old client reads: F1 only.
        let racing = try XCTUnwrap((object["racing"] as? [String: Any])?["events"] as? [[String: Any]])
        XCTAssertEqual(racing.compactMap { $0["idEvent"] as? String }, ["401"])
        let motorsport = try XCTUnwrap((object["motorsport"] as? [String: Any])?["events"] as? [[String: Any]])
        XCTAssertEqual(motorsport.compactMap { $0["idEvent"] as? String }, ["nascar-5630"])

        // What a current client reads: one racing bucket again.
        let decoded = try JSONDecoder().decode(LiveScore.self, from: data)
        XCTAssertEqual(Set(decoded.racing?.events.compactMap(\.idEvent) ?? []), ["401", "nascar-5630"])
    }

    func testRacingWithOnlyOtherSeriesStillSendsEmptyRacing() throws {
        let data = try JSONEncoder().encode(LiveScore(racing: LiveEvent(events: [cup])))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let racing = try XCTUnwrap((object["racing"] as? [String: Any])?["events"] as? [Any])
        XCTAssertTrue(racing.isEmpty, "nil and empty differ to a delta merge")
    }

    func testF1OnlyPayloadIsUnchanged() throws {
        let data = try JSONEncoder().encode(LiveScore(racing: LiveEvent(events: [f1])))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["motorsport"])
    }

    func testStockCarFieldsRoundTrip() throws {
        let entry = LeaderboardEntry(name: "Kyle Larson", score: "P1", position: 1, constructor: "Hendrick Motorsports",
                                     stockCar: StockCarDetail(carNumber: "5", manufacturer: "Chevrolet", lapsLed: 235))
        let session = EventSession(sessionType: "race", sessionName: "Race", status: "in", leaderboard: [entry],
                                   raceState: RaceState(lap: 135, totalLaps: 267, flag: .green, stage: 2))
        let decoded = try JSONDecoder().decode(EventSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded, session)
        XCTAssertEqual(decoded.importance, 6)
    }

    func testLiveActivityShowsLapForStockCars() throws {
        let entry = LeaderboardEntry(name: "Austin Cindric", score: "P1", position: 1,
                                     stockCar: StockCarDetail(carNumber: "2", manufacturer: "Ford"))
        let session = EventSession(sessionType: "race", sessionName: "Race", status: "in", leaderboard: [entry],
                                   raceState: RaceState(lap: 135, totalLaps: 267, flag: .green))
        let game = Game(idEvent: "nascar-5630", idLeague: "4393", strHomeTeam: "South Point 400", strAwayTeam: "Austin Cindric",
                        isoDate: nil, sessions: [session])
        let race = try XCTUnwrap(LiveActivityRace(game: game, standings: nil))
        XCTAssertEqual(race.session, "Lap 135/267")
        XCTAssertEqual(race.leaders.first?.code, "CIN")
        XCTAssertEqual(race.leaders.first?.teamColor, "1F5AA6")
    }

    func testDriverNameCleanup() {
        XCTAssertEqual(NASCARVocabulary.cleanDriverName("Austin Cindric (C)"), "Austin Cindric")
        XCTAssertEqual(NASCARVocabulary.cleanDriverName("Austin Hill(i)"), "Austin Hill")
        XCTAssertEqual(NASCARVocabulary.cleanDriverName("Connor Zilisch #"), "Connor Zilisch")
        XCTAssertEqual(NASCARVocabulary.manufacturer("Tyt"), "Toyota")
    }
}
