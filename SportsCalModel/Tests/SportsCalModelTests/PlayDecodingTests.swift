//
//  PlayDecodingTests.swift
//  SportsCalModelTests
//
//  Validates that ESPN's `/summary?event={id}` `plays[]` array decodes cleanly for
//  NBA, NFL, NHL, and MLB despite per-sport shape differences (e.g., MLB omits `clock`).
//

import XCTest
@testable import SportsCalModel

final class PlayDecodingTests: XCTestCase {

    func testNBASummaryDecodes() throws {
        let summary = try XCTUnwrap(
            try JSONLoader.load(file: "NBASummary", type: ESPNSummaryResponse.self) as? ESPNSummaryResponse
        )
        let plays = try XCTUnwrap(summary.plays)
        XCTAssertGreaterThan(plays.count, 5)

        let scoringPlays = plays.filter { $0.scoringPlay == true }
        XCTAssertFalse(scoringPlays.isEmpty, "Expected at least one scoring play")
        let firstScoring = try XCTUnwrap(scoringPlays.first)
        XCTAssertNotNil(firstScoring.homeScore)
        XCTAssertNotNil(firstScoring.awayScore)

        // NBA always includes clock.displayValue
        for play in plays {
            XCTAssertNotNil(play.clock?.displayValue, "NBA plays should include clock")
            XCTAssertNotNil(play.period?.number, "NBA plays should include period")
        }
    }

    func testNFLSummaryDecodes() throws {
        let summary = try XCTUnwrap(
            try JSONLoader.load(file: "NFLSummary", type: ESPNSummaryResponse.self) as? ESPNSummaryResponse
        )
        let plays = try XCTUnwrap(summary.plays)
        XCTAssertGreaterThan(plays.count, 5)

        let scoringPlays = plays.filter { $0.scoringPlay == true }
        XCTAssertFalse(scoringPlays.isEmpty)

        // NFL always has period.number (1-4, with 5=OT)
        for play in plays {
            XCTAssertNotNil(play.period?.number)
        }
    }

    func testNHLSummaryDecodes() throws {
        let summary = try XCTUnwrap(
            try JSONLoader.load(file: "NHLSummary", type: ESPNSummaryResponse.self) as? ESPNSummaryResponse
        )
        let plays = try XCTUnwrap(summary.plays)
        XCTAssertGreaterThan(plays.count, 5)

        // NHL can reach period 4 (OT) or 5 (shootout)
        let goalPlays = plays.filter { $0.type?.text == "Goal" }
        XCTAssertFalse(goalPlays.isEmpty, "Expected at least one goal in NHL fixture")

        // Validate OT period (4) exists in our fixture
        let overtimePlays = plays.filter { ($0.period?.number ?? 0) >= 4 }
        XCTAssertFalse(overtimePlays.isEmpty)
    }

    func testMLBSummaryDecodes() throws {
        // MLB commonly omits `clock` — decoder must not throw when it's absent.
        let summary = try XCTUnwrap(
            try JSONLoader.load(file: "MLBSummary", type: ESPNSummaryResponse.self) as? ESPNSummaryResponse
        )
        let plays = try XCTUnwrap(summary.plays)
        XCTAssertGreaterThan(plays.count, 5)

        // Confirm `clock` being absent is gracefully handled
        let playsWithoutClock = plays.filter { $0.clock == nil }
        XCTAssertFalse(playsWithoutClock.isEmpty, "MLB fixture should have plays without clock")

        // Period.number represents inning in MLB
        for play in plays {
            XCTAssertNotNil(play.period?.number)
        }

        // Home run scoring play should include updated scores
        let homeRun = plays.first(where: { $0.type?.text == "Home Run" })
        XCTAssertNotNil(homeRun)
        XCTAssertEqual(homeRun?.scoringPlay, true)
        XCTAssertNotNil(homeRun?.homeScore)
    }

    func testCachedPlaysRoundTrip() throws {
        // CachedPlays is what we serve from /plays/:eventID; ensure it round-trips cleanly.
        let plays: [Play] = [
            Play(
                id: "42",
                text: "LeBron makes 3",
                scoringPlay: true,
                awayScore: 3, homeScore: 0,
                clock: Play.PlayClock(displayValue: "11:42"),
                period: Play.PlayPeriod(number: 1),
                type: Play.PlayType(id: "131", text: "Three Point Jumper")
            )
        ]
        let cached = CachedPlays(
            eventID: "401705123",
            lastPlayId: "42",
            plays: plays,
            isFinal: false,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(cached)
        let decoded = try JSONDecoder().decode(CachedPlays.self, from: data)
        XCTAssertEqual(decoded, cached)
    }
}
