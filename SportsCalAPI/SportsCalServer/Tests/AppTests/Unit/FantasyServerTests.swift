//
//  FantasyServerTests.swift
//  AppTests
//
//  The fantasy game log (slates, season averages) and Sleeper → ESPN player matching.
//

import XCTest
@testable import App
import SportsCalModel

final class FantasyServerTests: XCTestCase {
    typealias K = FantasyStatKey.NFL

    private func line(_ athlete: String, event: String, team: String = "8", _ stats: [String: Double], state: String = "post") -> FantasyPlayerLine {
        FantasyPlayerLine(athleteID: athlete, name: "Player \(athlete)", teamID: team, eventID: event, stats: stats, gameState: state)
    }

    private func openArchive() async throws -> FantasyArchive {
        let archive = try await FantasyArchive.inMemory()
        addTeardownBlock { await archive.close() }
        return archive
    }

    private func slot(week: Int) -> FantasyArchive.Slot {
        .init(league: "nfl", season: 2026, seasonType: 2, week: week)
    }

    func testSlateAndAveragesExcludeTheSlatesOwnGames() async throws {
        let archive = try await openArchive()
        try await archive.replace(eventID: "w1", slot: slot(week: 1), isFinal: true,
                                  lines: [line("a", event: "w1", [K.rushingYards: 100])])
        try await archive.replace(eventID: "w2", slot: slot(week: 2), isFinal: true,
                                  lines: [line("a", event: "w2", [K.rushingYards: 50, K.rushingTouchdowns: 1])])
        try await archive.replace(eventID: "w3", slot: slot(week: 3), isFinal: false,
                                  lines: [line("a", event: "w3", [K.rushingYards: 10], state: "in"),
                                          line("b", event: "w3", [K.receptions: 3], state: "in")])

        let week3 = try await archive.lines(slot: slot(week: 3))
        XCTAssertEqual(Set(week3.map(\.athleteID)), ["a", "b"])

        let averages = try await archive.seasonAverages(league: "nfl", season: 2026, athleteIDs: ["a", "b"], excludingEvents: ["w3"])
        XCTAssertEqual(averages["a"]?.games, 2)
        XCTAssertEqual(averages["a"]?.stats[K.rushingYards], 75)
        XCTAssertEqual(averages["a"]?.stats[K.rushingTouchdowns], 0.5)
        XCTAssertNil(averages["b"], "a live game isn't history")

        let weeks = try await archive.weeks(league: "nfl", season: 2026, seasonType: 2)
        XCTAssertEqual(weeks, [1, 2, 3])
        let finals = try await archive.finalEventIDs(league: "nfl", season: 2026, seasonType: 2)
        XCTAssertEqual(finals, ["w1", "w2"])
    }

    func testReplaceDropsPlayersNoLongerInTheBox() async throws {
        let archive = try await openArchive()
        try await archive.replace(eventID: "g", slot: slot(week: 1), isFinal: false,
                                  lines: [line("a", event: "g", [:]), line("b", event: "g", [:])])
        try await archive.replace(eventID: "g", slot: slot(week: 1), isFinal: true, lines: [line("a", event: "g", [:])])
        let lines = try await archive.lines(eventID: "g")
        XCTAssertEqual(lines.map(\.athleteID), ["a"])
    }

    func testConcurrentWritesDontCollide() async throws {
        let archive = try await openArchive()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for game in 0..<20 {
                group.addTask {
                    try await archive.replace(eventID: "g\(game)", slot: self.slot(week: 1), isFinal: true,
                                              lines: (0..<5).map { self.line("p\(game)-\($0)", event: "g\(game)", [K.receptions: 1]) })
                }
            }
            try await group.waitForAll()
        }
        let lines = try await archive.lines(slot: slot(week: 1))
        XCTAssertEqual(lines.count, 100)
    }

    // MARK: Sleeper matching

    func testSleeperMatcher() {
        let rosters = FantasyRosterSet(
            updated: Date(),
            athletes: [
                "4431611": .init(athleteID: "4431611", name: "Caleb Williams", position: "QB", jersey: "18", teamID: "3", teamAbbreviation: "CHI"),
                "100": .init(athleteID: "100", name: "Josh Allen", position: "QB", jersey: "17", teamID: "2", teamAbbreviation: "BUF"),
                "200": .init(athleteID: "200", name: "Josh Allen", position: "LB", jersey: "41", teamID: "30", teamAbbreviation: "JAX"),
                "300": .init(athleteID: "300", name: "Terry McLaurin", position: "WR", jersey: "17", teamID: "28", teamAbbreviation: "WSH"),
            ],
            teams: ["CHI": "3", "BUF": "2", "JAX": "30", "WSH": "28", "DET": "8"]
        )
        let players: [String: SleeperImport.Player] = [
            "11560": .init(name: "Caleb Williams", team: "CHI", number: "18", position: "QB", espnID: nil),
            "4984": .init(name: "Josh Allen", team: "BUF", number: "17", position: "QB", espnID: nil),
            "5848": .init(name: "Terry McLaurin", team: "WAS", number: "17", position: "WR", espnID: nil),
            "999": .init(name: "Someone", team: "BUF", number: "1", position: "RB", espnID: "4242"),
            "777": .init(name: "Nobody Known", team: nil, number: nil, position: "WR", espnID: nil),
        ]
        let matcher = SleeperImport.Matcher(players: players, rosters: rosters)
        XCTAssertEqual(matcher.espnID(sleeperID: "11560"), "4431611")
        XCTAssertEqual(matcher.espnID(sleeperID: "4984"), "100", "team disambiguates two Josh Allens")
        XCTAssertEqual(matcher.espnID(sleeperID: "5848"), "300", "WAS is ESPN's WSH")
        XCTAssertEqual(matcher.espnID(sleeperID: "999"), "4242", "Sleeper's espn_id wins")
        XCTAssertEqual(matcher.espnID(sleeperID: "DET"), "dst-8")
        XCTAssertNil(matcher.espnID(sleeperID: "777"))
        XCTAssertEqual(matcher.describe(sleeperID: "777"), "Nobody Known (WR)")
    }

    func testRosterPositionsFillKickers() {
        let rosters = FantasyRosterSet(
            updated: Date(),
            athletes: ["k": .init(athleteID: "k", name: "Jake Bates", position: "PK", jersey: "39", teamID: "8", teamAbbreviation: "DET")],
            teams: [:]
        )
        let filled = rosters.fillPositions([line("k", event: "g", [K.fieldGoalsMade: 2])])
        XCTAssertEqual(filled.first?.position, "K")
    }

    func testUsernameValidation() {
        XCTAssertTrue(SleeperImport.isValidUsername("fantasy_guru99"))
        XCTAssertFalse(SleeperImport.isValidUsername("../league/1"))
        XCTAssertFalse(SleeperImport.isValidUsername(""))
        XCTAssertTrue(SleeperImport.isValidID("1180234567890"))
        XCTAssertFalse(SleeperImport.isValidID("12a"))
    }
}
