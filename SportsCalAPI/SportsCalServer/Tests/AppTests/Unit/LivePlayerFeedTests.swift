//
//  LivePlayerFeedTests.swift
//  AppTests
//
//  The server-only feed custom player alerts read: built from the ESPN summary the
//  play-by-play job already fetches, and kept off everything clients are served.
//

import XCTest
@testable import App
import SportsCalModel

final class LivePlayerFeedTests: XCTestCase {

    /// A trimmed ESPN NBA summary: a made three with an assist, a play nobody's
    /// named on, and the shooter's box-score line.
    private let summaryJSON = """
    {
      "plays": [
        {"id": "1", "text": "Jump ball", "type": {"id": "615", "text": "Jumpball"},
         "period": {"number": 1}, "clock": {"displayValue": "12:00"}},
        {"id": "2", "text": "Stephen Curry makes 26-foot three point jumper (Draymond Green assists)",
         "scoringPlay": true, "awayScore": 3, "homeScore": 0,
         "type": {"id": "92", "text": "Jump Shot"}, "period": {"number": 1}, "clock": {"displayValue": "11:41"},
         "participants": [{"athlete": {"id": "3975"}}, {"athlete": {"id": "6589"}}]}
      ],
      "boxscore": {
        "teams": [{"team": {"id": "9", "abbreviation": "GS"}, "homeAway": "away"}],
        "players": [{
          "team": {"id": "9", "abbreviation": "GS"},
          "statistics": [{
            "keys": ["minutes", "points", "threePointFieldGoalsMade-threePointFieldGoalsAttempted", "assists"],
            "labels": ["MIN", "PTS", "3PT", "AST"],
            "athletes": [
              {"athlete": {"id": "3975", "displayName": "Stephen Curry", "shortName": "S. Curry"},
               "starter": true, "stats": ["1", "3", "1-1", "0"]},
              {"athlete": {"id": "6589", "displayName": "Draymond Green", "shortName": "D. Green"},
               "starter": true, "stats": ["1", "0", "0-0", "1"]},
              {"athlete": {"id": "1", "displayName": "Sat Out"}, "didNotPlay": true, "stats": []}
            ]
          }]
        }]
      }
    }
    """

    private func summary() throws -> ESPNSummaryResponse {
        try JSONDecoder().decode(ESPNSummaryResponse.self, from: Data(summaryJSON.utf8))
    }

    private func feed(_ summary: ESPNSummaryResponse, sport: SportType? = .basketball) -> LivePlayerFeed? {
        LivePlayerFeed(
            summary: summary, sportType: sport, espnEventID: "401", tsdbEventID: "2001",
            sport: "basketball", league: "nba", isFinal: false, fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testFeedNamesPlayAthletesAndKeepsLiveStats() throws {
        let feed = try XCTUnwrap(feed(try summary()))
        XCTAssertEqual(feed.plays, [
            .init(playID: "2", participants: [
                PlayParticipant(athleteID: "3975", name: "S. Curry"),
                PlayParticipant(athleteID: "6589", name: "D. Green"),
            ]),
        ], "Only plays that name someone; names filled from the box score")
        XCTAssertEqual(feed.statLines.map(\.athleteID), ["3975", "6589"], "Players who sat have no line")
        let curry = try XCTUnwrap(feed.statLines.first)
        XCTAssertEqual(curry.stats["points"], 3)
        XCTAssertEqual(curry.stats["threePointFieldGoalsMade"], 1)
        XCTAssertEqual(curry.teamID, "9")

        let decoded = try JSONDecoder().decode(LivePlayerFeed.self, from: try JSONEncoder().encode(feed))
        XCTAssertEqual(decoded, feed)
    }

    func testNoFeedWithoutAthletes() throws {
        let empty = try JSONDecoder().decode(ESPNSummaryResponse.self, from: Data(#"{"plays": [{"id": "1"}]}"#.utf8))
        XCTAssertNil(feed(empty))
        // Participants alone are still worth keeping (no box score yet).
        XCTAssertNotNil(feed(try summary(), sport: nil))
    }

    func testServedPlaysDropParticipants() throws {
        let summary = try summary()
        XCTAssertNotNil(summary.allPlays.last?.participants)
        let served = CachedPlays(eventID: "2001", lastPlayId: "2", plays: summary.allPlays, isFinal: false, fetchedAt: Date())
        let json = String(decoding: try JSONEncoder().encode(served), as: UTF8.self)
        XCTAssertFalse(json.contains("participants"))
        XCTAssertFalse(json.contains("3975"))
    }

    func testRedisKeys() {
        XCTAssertEqual(RedisEndpoint.ESPN.livePlayers("401").getValue(isDebug: false), "LivePlayers-401")
        XCTAssertEqual(RedisEndpoint.ESPN.livePlayers("401").getValue(isDebug: true), "debug-LivePlayers-401")
    }
}
