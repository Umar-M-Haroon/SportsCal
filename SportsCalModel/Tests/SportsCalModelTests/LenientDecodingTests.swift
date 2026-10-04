import XCTest
@testable import SportsCalModel

/// Lenient schedule decoding: one malformed game or enrichment blob must not fail the
/// whole `LiveScore`, every recovery is reported, and encoding is untouched.
final class LenientDecodingTests: XCTestCase {

    override func tearDown() {
        LiveScore.decodeIssueHandler = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func game(_ id: String, league: Leagues = .nba, extra: String = "") -> String {
        """
        {"idEvent":"\(id)","idLeague":"\(league.rawValue)","strHomeTeam":"Home \(id)","strAwayTeam":"Away \(id)",\
        "intHomeScore":"1","intAwayScore":"0","strStatus":"pre","strTimestamp":"2026-10-04T19:00:00Z"\(extra)}
        """
    }

    private func decodeCollecting(_ json: String) throws -> (value: LiveScore, issues: [DecodeIssue]) {
        try ModelDecodeDiagnostics.collecting {
            try JSONDecoder().decode(LiveScore.self, from: Data(json.utf8))
        }
    }

    private func sampleGame(_ id: String, league: Leagues, home: String = "Home", away: String = "Away") -> Game {
        Game(
            idEvent: id, idLeague: "\(league.rawValue)", idHomeTeam: "h\(id)", idAwayTeam: "a\(id)",
            strHomeTeam: home, strAwayTeam: away, intHomeScore: "21", intAwayScore: "17",
            strStatus: "post", strProgress: "Final", strTimestamp: "2026-10-04T19:00:00Z",
            homeLinescores: [7, 7, 0, 7], awayLinescores: [3, 7, 7, 0],
            isCompleted: true, isoDate: Date(timeIntervalSinceReferenceDate: 812_833_200),
            venueName: "Stadium", homeRecord: "3-1", awayRecord: "2-2"
        )
    }

    // MARK: - Malformed games

    func testOneMalformedGameIsSkippedAndTheRestDecode() throws {
        let good = """
        {"nba":{"events":[\(game("1")),\(game("2")),\(game("3"))]},"nhl":{"events":[\(game("10", league: .nhl))]}}
        """
        let bad = """
        {"nba":{"events":[\(game("1")),{"idEvent":"2","strHomeTeam":42,"strAwayTeam":"Away"},\(game("3"))]},\
        "nhl":{"events":[\(game("10", league: .nhl))]}}
        """
        let baseline = try decodeCollecting(good)
        let lenient = try decodeCollecting(bad)
        XCTAssertTrue(baseline.issues.isEmpty)
        XCTAssertEqual(baseline.value.nba?.events.count, 3)
        XCTAssertEqual(lenient.value.nba?.events.count, 2, "exactly the malformed game drops")
        XCTAssertEqual(lenient.value.nba?.events.map(\.idEvent), ["1", "3"])
        XCTAssertEqual(lenient.value.nhl, baseline.value.nhl, "other sports are untouched")

        let issue = try XCTUnwrap(lenient.issues.first)
        XCTAssertEqual(lenient.issues.count, 1)
        XCTAssertEqual(issue.kind, .skippedElement)
        XCTAssertEqual(issue.path, "nba.events[1]")
        XCTAssertEqual(issue.idEvent, "2", "the skipped game's id is read for the report")
        XCTAssertTrue(issue.reason.contains("strHomeTeam"), issue.reason)
    }

    func testNullAndNonObjectElementsAreSkipped() throws {
        let json = #"{"nba":{"events":[null,\#(game("1")),7,"x",[1],\#(game("2"))]}}"#
        let result = try decodeCollecting(json)
        XCTAssertEqual(result.value.nba?.events.map(\.idEvent), ["1", "2"])
        XCTAssertEqual(result.issues.map(\.path), ["nba.events[0]", "nba.events[2]", "nba.events[3]", "nba.events[4]"])
        XCTAssertTrue(result.issues.allSatisfy { $0.idEvent == nil })
    }

    func testRealScheduleDropsOnlyTheCorruptedGame() throws {
        // The ~25MB production snapshot: corrupt one NBA-or-other game and confirm the
        // count drops by exactly one.
        let url = URL(fileURLWithPath: #file).deletingLastPathComponent()
            .appendingPathComponent("MockJSON/FullScheduleSnapshot.json")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("FullScheduleSnapshot.json not present") }
        let original = try ModelDecodeDiagnostics.collecting { try JSONDecoder().decode(LiveScore.self, from: data) }
        XCTAssertTrue(original.issues.isEmpty, "the real snapshot decodes cleanly: \(original.issues.prefix(3))")

        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sport = try XCTUnwrap(["nba", "mlb", "nfl", "nhl", "soccer"].first {
            ((root[$0] as? [String: Any])?["events"] as? [Any])?.isEmpty == false
        })
        var bucket = try XCTUnwrap(root[sport] as? [String: Any])
        var events = try XCTUnwrap(bucket["events"] as? [[String: Any]])
        events[0]["intHomeScore"] = ["not": "a string"]
        bucket["events"] = events
        root[sport] = bucket
        let corrupted = try JSONSerialization.data(withJSONObject: root)

        let lenient = try ModelDecodeDiagnostics.collecting { try JSONDecoder().decode(LiveScore.self, from: corrupted) }
        let before = try XCTUnwrap(original.value.event(for: Self.sportType(sport))?.events.count)
        XCTAssertEqual(lenient.value.event(for: Self.sportType(sport))?.events.count, before - 1)
        XCTAssertEqual(lenient.issues.count, 1)
        XCTAssertEqual(lenient.issues.first?.path, "\(sport).events[0]")
    }

    private static func sportType(_ key: String) -> SportType {
        switch key {
        case "nba": return .basketball
        case "mlb": return .mlb
        case "nfl": return .nfl
        case "nhl": return .hockey
        default: return .soccer
        }
    }

    // MARK: - Enrichment blobs and buckets

    func testMalformedF1StandingsBecomesNilAndScheduleStillDecodes() throws {
        let json = """
        {"racing":{"events":[\(game("f1", league: .formula1))]},"nba":{"events":[\(game("1"))]},\
        "f1Standings":{"driverStandings":"oops","constructorStandings":[]},"worldCup":17}
        """
        let result = try decodeCollecting(json)
        XCTAssertNil(result.value.f1Standings)
        XCTAssertNil(result.value.worldCup)
        XCTAssertEqual(result.value.racing?.events.count, 1)
        XCTAssertEqual(result.value.nba?.events.count, 1)
        XCTAssertEqual(Set(result.issues.map(\.path)), ["f1Standings", "worldCup"])
        XCTAssertTrue(result.issues.allSatisfy { $0.kind == .droppedField })
    }

    func testValidF1StandingsStillDecode() throws {
        let json = #"{"f1Standings":{"driverStandings":[],"constructorStandings":[],"round":12}}"#
        let result = try decodeCollecting(json)
        XCTAssertEqual(result.value.f1Standings?.round, 12)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testBrokenBucketDropsOnlyThatSport() throws {
        let json = """
        {"mlb":{"evnts":[]},"golf":[1,2],"nba":{"events":[\(game("1"))]},"nhl":{"events":[\(game("2", league: .nhl))]}}
        """
        let result = try decodeCollecting(json)
        XCTAssertNil(result.value.mlb)
        XCTAssertNil(result.value.golf)
        XCTAssertEqual(result.value.nba?.events.count, 1)
        XCTAssertEqual(result.value.nhl?.events.count, 1)
        XCTAssertEqual(Set(result.issues.map(\.path)), ["mlb", "golf"])
    }

    func testMalformedGameExtraKeepsTheGame() throws {
        // Display extras read as nil; the game itself survives.
        let extra = #","circuitInfo":"bad","homeLeaders":{"x":1},"homeLinescores":["a"],"playoff":[],"venueName":"Arena""#
        let result = try decodeCollecting(#"{"nba":{"events":[\#(game("1", extra: extra))]}}"#)
        let decoded = try XCTUnwrap(result.value.nba?.events.first)
        XCTAssertNil(decoded.circuitInfo)
        XCTAssertNil(decoded.homeLeaders)
        XCTAssertNil(decoded.homeLinescores)
        XCTAssertNil(decoded.playoff)
        XCTAssertEqual(decoded.venueName, "Arena")
        XCTAssertEqual(Set(result.issues.map(\.path)), [
            "nba.events[0].circuitInfo", "nba.events[0].homeLeaders",
            "nba.events[0].homeLinescores", "nba.events[0].playoff",
        ])
    }

    func testRootThatIsNotAnObjectStillThrows() {
        XCTAssertThrowsError(try JSONDecoder().decode(LiveScore.self, from: Data("[]".utf8)))
    }

    func testIndividualSportStrEventFallbackIsPreserved() throws {
        let json = #"{"golf":{"events":[{"idEvent":"g1","idLeague":"4425","strEvent":"The Masters","strHomeTeam":null,"strAwayTeam":null}]}}"#
        let result = try decodeCollecting(json)
        let golf = try XCTUnwrap(result.value.golf?.events.first)
        XCTAssertEqual(golf.strHomeTeam, "The Masters")
        XCTAssertEqual(golf.strAwayTeam, "TBD")
        XCTAssertTrue(result.issues.isEmpty)
    }

    // MARK: - Reporting

    func testHandlerGetsOneSummaryPerLiveScoreDecode() throws {
        var reports: [String] = []
        let lock = NSLock()
        LiveScore.decodeIssueHandler = { message in lock.lock(); reports.append(message); lock.unlock() }
        let json = """
        {"nba":{"events":[{"idEvent":"x","strHomeTeam":1},\(game("1")),null]},"nfl":{"events":[5]},"f1Standings":3}
        """
        let score = try JSONDecoder().decode(LiveScore.self, from: Data(json.utf8))
        XCTAssertEqual(score.nba?.events.count, 1)
        XCTAssertEqual(reports.count, 1, "batched into one report")
        let report = try XCTUnwrap(reports.first)
        XCTAssertTrue(report.contains("4 issue(s)"), report)
        XCTAssertTrue(report.contains("skipped 3 element(s) [nba×2, nfl×1]"), report)
        XCTAssertTrue(report.contains("dropped 1 field(s)"), report)
        XCTAssertTrue(report.contains("idEvent x"), report)

        // A clean decode doesn't call the handler.
        _ = try JSONDecoder().decode(LiveScore.self, from: Data(#"{"nba":{"events":[\#(game("1"))]}}"#.utf8))
        XCTAssertEqual(reports.count, 1)
    }

    func testCollectingScopeSuppressesTheHandler() throws {
        var calls = 0
        ModelDecodeDiagnostics.issueHandler = { _ in calls += 1 }
        let result = try decodeCollecting(#"{"nba":{"events":[null]}}"#)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(calls, 0)
    }

    func testStandaloneLiveEventReportsEachIssue() throws {
        var reports: [String] = []
        LiveScore.decodeIssueHandler = { reports.append($0) }
        let event = try JSONDecoder().decode(LiveEvent.self, from: Data(#"{"events":[1,\#(game("1")),2]}"#.utf8))
        XCTAssertEqual(event.events.count, 1)
        XCTAssertEqual(reports.count, 2)
    }

    // MARK: - Round trips

    func testLiveScoreRoundTripSplitsAndFoldsCollegeFootball() throws {
        let nfl = sampleGame("401", league: .nfl, home: "Chiefs", away: "Bills")
        let college = sampleGame("501", league: .ncaaf, home: "Georgia", away: "Alabama")
        let score = LiveScore(
            nba: LiveEvent(events: [sampleGame("1", league: .nba)]),
            nfl: LiveEvent(events: [nfl, college]),
            f1Standings: F1Standings(driverStandings: [], constructorStandings: [])
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(score)

        // On the wire: college under `ncaaf`, pros under `nfl`.
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let wireNFL = try XCTUnwrap((root["nfl"] as? [String: Any])?["events"] as? [[String: Any]])
        let wireNCAAF = try XCTUnwrap((root["ncaaf"] as? [String: Any])?["events"] as? [[String: Any]])
        XCTAssertEqual(wireNFL.compactMap { $0["idEvent"] as? String }, ["401"])
        XCTAssertEqual(wireNCAAF.compactMap { $0["idEvent"] as? String }, ["501"])

        // Back in memory: one football bucket again.
        let decoded = try decodeCollecting(String(decoding: data, as: UTF8.self))
        XCTAssertTrue(decoded.issues.isEmpty)
        XCTAssertEqual(decoded.value.nfl?.events.map(\.idEvent), ["401", "501"])
        XCTAssertEqual(decoded.value, score)
        // Encoding is stable across the trip.
        XCTAssertEqual(try encoder.encode(decoded.value), data)
    }

    func testCollegeOnlyBucketStillSendsEmptyNFL() throws {
        let score = LiveScore(nfl: LiveEvent(events: [sampleGame("501", league: .ncaaf)]))
        let data = try JSONEncoder().encode(score)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(((root["nfl"] as? [String: Any])?["events"] as? [Any])?.count, 0)
        XCTAssertEqual(try JSONDecoder().decode(LiveScore.self, from: data), score)
    }

    func testLiveEventEncodingShape() throws {
        let event = LiveEvent(events: [sampleGame("1", league: .nba)])
        let data = try JSONEncoder().encode(event)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Array(root.keys), ["events"])
        XCTAssertEqual(try JSONDecoder().decode(LiveEvent.self, from: data), event)
    }

    func testGameRoundTrip() throws {
        var game = Game(
            idEvent: "9", idLeague: "\(Leagues.nba.rawValue)", idHomeTeam: "h9", idAwayTeam: "a9",
            strHomeTeam: "Lakers", strAwayTeam: "Nuggets", intHomeScore: "110", intAwayScore: "104",
            strStatus: "post", strProgress: "Final", strTimestamp: "2027-05-20T01:30:00Z",
            homeLinescores: [30, 25, 28, 27], awayLinescores: [24, 30, 26, 24],
            homeLeaders: [GameLeader(category: "points", categoryDisplay: "PTS", playerName: "A", displayValue: "30")],
            isCompleted: true, isoDate: Date(timeIntervalSinceReferenceDate: 832_555_800),
            homeSeed: 2, awaySeed: 1,
            playoff: PlayoffContext(seriesTitle: "West Finals", gameNumber: 3, bestOf: 7),
            season: "2026-2027", seasonPhase: .postseason, excitement: 72
        )
        let data = try JSONEncoder().encode(game)
        XCTAssertEqual(try JSONDecoder().decode(Game.self, from: data), game)
        // No phase (what `.regular` also encodes as) round-trips too.
        game.seasonPhase = nil
        XCTAssertEqual(try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game)), game)
    }

    func testIndividualSportGameRoundTrip() throws {
        let game = Game(
            idEvent: "r1", idLeague: "\(Leagues.formula1.rawValue)",
            strHomeTeam: "Monaco Grand Prix", strAwayTeam: "M. Verstappen",
            strStatus: "in", strTimestamp: "2026-05-24T13:00:00Z",
            lastPlay: "M. Verstappen|1|Leader|Red Bull", isCompleted: false,
            isoDate: Date(timeIntervalSinceReferenceDate: 801_320_400),
            circuitInfo: F1CircuitInfo(circuitName: "Circuit de Monaco", locality: "Monte Carlo", country: "Monaco")
        )
        let data = try JSONEncoder().encode(game)
        XCTAssertEqual(try JSONDecoder().decode(Game.self, from: data), game)
    }
}
