import XCTest
@testable import SportsCalModel

/// `Game` is copy-on-write over a shared storage box: pointer-sized, value semantics,
/// and the same wire format and equality as the old all-inline struct.
final class GameStorageTests: XCTestCase {

    /// Every encodable field set. Live soccer so `situation` and `intRound` are on the
    /// wire; `timeTBD` only encodes for a not-started game and `lastPlayScoreboardID`
    /// never does, so they stay nil to keep the round trip exact.
    static func fullyPopulatedGame() -> Game {
        let entry = LeaderboardEntry(name: "Driver", score: "-3", position: 1, headshot: "h.png", thruHole: "F",
                                     rounds: ["70", "68"], constructor: "Team", gap: "+1.2", isCut: false,
                                     movement: 2, flagURL: "f.png", flagAlt: "GB", teeTime: "9:00",
                                     qualifyingTimes: ["1:20.1"], today: "-2", teeTimeDate: "2026-11-22T09:00:00Z")
        return Game(
            idLiveScore: "ls1", idEvent: "ev1", strSport: nil, idLeague: "\(Leagues.English_Premier_League.rawValue)",
            strLeague: nil, idHomeTeam: "h1", idAwayTeam: "a1", strHomeTeam: "Arsenal", strAwayTeam: "Chelsea",
            strHomeTeamBadge: "hb.png", strAwayTeamBadge: "ab.png", intHomeScore: "2", intAwayScore: "1",
            strStatus: "in", strProgress: "67'", strTimestamp: "2026-11-22T15:00:00Z", lastPlay: "Goal!",
            homeLinescores: [1, 1], awayLinescores: [0, 1],
            homeLeaders: [GameLeader(category: "goals", categoryDisplay: "Goals", playerName: "Saka", displayValue: "2", headshot: "s.png")],
            awayLeaders: [GameLeader(category: "goals", categoryDisplay: "Goals", playerName: "Palmer", displayValue: "1")],
            isCompleted: false, isoDate: Date(timeIntervalSinceReferenceDate: 816_000_000.5),
            leaderboardEntries: [entry],
            sessions: [EventSession(sessionType: "R", sessionName: "Race", status: "in", progress: "L10", date: "2026-11-22T15:00:00Z",
                                    leaderboard: [entry], raceState: .init(lap: 10, totalLaps: 50, flag: .green))],
            venueName: "Emirates", homeTeamColor: "ff0000", awayTeamColor: "0000ff", homeRecord: "10-2-1", awayRecord: "8-3-2",
            circuitInfo: F1CircuitInfo(circuitName: "Silverstone", locality: "Silverstone", country: "UK",
                                       circuitImageURL: "c.png", latitude: "52.0", longitude: "-1.0"),
            golfCourseInfo: GolfCourseInfo(courseName: "Augusta", par: 72, holePars: [4, 5, 3], purse: "$1", defendingChampion: "X",
                                           numberOfRounds: 4, cutRound: 2, cutScore: 1, cutCount: 50, yardage: 7500),
            legDisplay: "1st Leg", aggregateScore: "3-2", homeSeed: 1, awaySeed: 4,
            homeConference: "sec", awayConference: "bigTen", tournamentName: "Cup", round: "Final", drawSlug: "mens-singles",
            homeInjuries: [InjuryReport(playerName: "A", position: "F", status: "Out", detail: "Knee", comment: "c",
                                        headshot: "i.png", returnDate: "2026-12-01", date: "2026-11-20")],
            awayInjuries: [InjuryReport(playerName: "B", status: "Questionable")],
            raceTiming: F1RaceTiming(sessionKey: 9, sessionType: "Race",
                                     drivers: [F1TelemetryDriver(driverNumber: 1, name: "Max", nameAcronym: "VER", teamName: "RB",
                                                                 stints: [F1Stint(stintNumber: 1, lapStart: 1, lapEnd: 20, compound: "SOFT")],
                                                                 pitStops: [F1PitStop(lapNumber: 20, pitDuration: 2.4)])]),
            playoff: PlayoffContext(seriesTitle: "Final", gameNumber: 1, bestOf: 7, homeWins: 0, awayWins: 0,
                                    seriesCompleted: false, isNeutralSite: true),
            lastPlayScoreboardID: nil, endDate: "2026-11-23T00:00:00Z", season: "2026-2027", seasonPhase: .postseason,
            sportsDBRound: 12,
            situation: GameSituation(period: 2, clock: 4020, possession: .home, lastPlaySide: .home, homeWinProbability: 0.7, tieProbability: 0.2),
            excitement: 88,
            scoreboardExtras: ScoreboardExtras(homeWinner: nil, awayWinner: nil,
                                               soccerDetails: [MatchIncident(kind: .goal, clock: "12'", athlete: "Saka", side: .home)],
                                               broadcasts: ["Sky"], homeAggregate: 3, awayAggregate: 2),
            homeAbbreviation: "ARS", awayAbbreviation: "CHE", timeTBD: nil
        )
    }

    private func encode(_ game: Game) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(game)
    }

    func testStrideIsPointerSized() {
        print("MemoryLayout<Game>.stride =", MemoryLayout<Game>.stride)
        XCTAssertLessThanOrEqual(MemoryLayout<Game>.stride, 16)
    }

    func testFullyPopulatedGameRoundTripsThroughJSON() throws {
        let game = Self.fullyPopulatedGame()
        let data = try encode(game)
        let decoded = try JSONDecoder().decode(Game.self, from: data)
        XCTAssertEqual(decoded, game)
        XCTAssertEqual(decoded.hashValue, game.hashValue)
        XCTAssertEqual(try encode(decoded), data)

        // Every optional key the encoder can emit is present, so nothing was dropped.
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["circuitInfo", "golfCourseInfo", "playoff", "situation", "extras", "raceTiming",
                    "sessions", "leaderboardEntries", "intRound", "seasonPhase", "strSeason", "excitement"] {
            XCTAssertNotNil(object[key], key)
        }
    }

    func testMutatingACopyLeavesTheOriginalAlone() {
        let original = Self.fullyPopulatedGame()
        var copy = original
        XCTAssertEqual(copy, original)

        copy.tournamentName = "Other Cup"
        copy.leaderboardEntries?.append(LeaderboardEntry(name: "Second", score: "E", position: 2))
        copy.situation = nil
        copy.golfCourseInfo?.purse = "$2"

        XCTAssertEqual(original.tournamentName, "Cup")
        XCTAssertEqual(original.leaderboardEntries?.count, 1)
        XCTAssertNotNil(original.situation)
        XCTAssertEqual(original.golfCourseInfo?.purse, "$1")
        XCTAssertEqual(copy.tournamentName, "Other Cup")
        XCTAssertEqual(copy.leaderboardEntries?.count, 2)
        XCTAssertNotEqual(copy, original)

        // Structural equality, not identity: an independently built equal game is equal.
        XCTAssertEqual(Self.fullyPopulatedGame(), original)
        XCTAssertEqual(Set([original, Self.fullyPopulatedGame()]).count, 1)
    }
}
