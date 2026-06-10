@testable import App
import XCTest
import SportsCalModel

/// Pins the World Cup enrichment helpers: write-guards (never clobber good data with
/// empties), bracket construction from an ESPN-shaped scoreboard (group games excluded,
/// knockout rounds ordered, third-place split out, winner detection), and scorer parsing.
final class WorldCupEnrichmentTests: XCTestCase {

    // MARK: - Write guards

    func test_emptyBracket_notPersisted() {
        XCTAssertFalse(WorldCupEnrichmentJob.shouldPersistBracket(WorldCupBracket()))
    }

    func test_nonEmptyBracket_persisted() {
        let bracket = WorldCupBracket(rounds: [
            WorldCupBracketRound(roundName: "Final", slug: "final", matches: [WorldCupBracketMatch()])
        ])
        XCTAssertTrue(WorldCupEnrichmentJob.shouldPersistBracket(bracket))
    }

    func test_emptyScorers_notPersisted() {
        XCTAssertFalse(WorldCupEnrichmentJob.shouldPersistScorers([]))
    }

    func test_nonEmptyScorers_persisted() {
        XCTAssertTrue(WorldCupEnrichmentJob.shouldPersistScorers([
            WorldCupScorer(rank: 1, playerName: "Mbappé", teamName: "France", goals: 8)
        ]))
    }

    // MARK: - Round ordering

    func test_roundSortIndex_ordersKnockoutRounds() throws {
        let r32 = try XCTUnwrap(WorldCupEnrichmentJob.roundSortIndex("Round of 32"))
        let r16 = try XCTUnwrap(WorldCupEnrichmentJob.roundSortIndex("Round of 16"))
        let qf = try XCTUnwrap(WorldCupEnrichmentJob.roundSortIndex("Quarterfinals"))
        let sf = try XCTUnwrap(WorldCupEnrichmentJob.roundSortIndex("Semifinals"))
        let final = try XCTUnwrap(WorldCupEnrichmentJob.roundSortIndex("Final"))
        XCTAssertTrue(r32 < r16 && r16 < qf && qf < sf && sf < final)
    }

    func test_roundSortIndex_groupStageIsNotABracketRound() {
        XCTAssertNil(WorldCupEnrichmentJob.roundSortIndex("Group A"))
        XCTAssertNil(WorldCupEnrichmentJob.roundSortIndex(nil))
    }

    // MARK: - Bracket construction

    func test_buildBracket_excludesGroups_ordersRounds_splitsThirdPlace() throws {
        let scoreboard = try JSONDecoder().decode(Scoreboard.self, from: Self.scoreboardJSON)
        let bracket = WorldCupEnrichmentJob.buildBracket(from: scoreboard)

        // Group game excluded; only R16 + Final remain as rounds.
        XCTAssertEqual(bracket.rounds.map(\.roundName), ["Round of 16", "Final"])

        // Third-place playoff split into its own slot.
        XCTAssertNotNil(bracket.thirdPlacePlayoff)

        // Winner detection from scores (R16: home 2 - away 1 → home).
        let r16 = try XCTUnwrap(bracket.rounds.first)
        let match = try XCTUnwrap(r16.matches.first)
        XCTAssertEqual(match.winner, .home)
        XCTAssertEqual(match.homeTeamName, "Brazil")
        XCTAssertEqual(match.awayTeamName, "Croatia")
    }

    // MARK: - Scorers

    func test_buildScorers_parsesGoalsCategory() {
        let leaders = LeadersResponse(leaders: [
            LeadersResponse.LeaderCategory(
                name: "goals", displayName: "Goals", abbreviation: "G",
                leaders: [
                    LeadersResponse.LeaderEntry(
                        displayValue: "8",
                        athlete: LeadersResponse.LeaderAthlete(id: "1", displayName: "Kylian Mbappé", shortName: "Mbappé", headshot: nil, position: nil),
                        team: LeadersResponse.LeaderTeam(id: "10", displayName: "France", abbreviation: "FRA", color: nil, logos: nil)
                    )
                ]
            )
        ])
        let scorers = WorldCupEnrichmentJob.buildScorers(from: leaders)
        XCTAssertEqual(scorers.count, 1)
        XCTAssertEqual(scorers.first?.rank, 1)
        XCTAssertEqual(scorers.first?.playerName, "Kylian Mbappé")
        XCTAssertEqual(scorers.first?.teamName, "France")
        XCTAssertEqual(scorers.first?.goals, 8)
    }

    // MARK: - Fixture

    private static func event(id: String, note: String, home: String, away: String, homeScore: String, awayScore: String, completed: Bool, seasonType: Int = 3) -> String {
        """
        {
          "id": "\(id)", "uid": "u\(id)", "date": "2026-07-05T19:00Z", "name": "\(home) vs \(away)",
          "season": { "year": 2026, "type": \(seasonType) },
          "competitions": [{
            "id": "c\(id)", "uid": "uc\(id)", "date": "2026-07-05T19:00Z",
            "notes": [{ "headline": "\(note)" }],
            "status": { "type": { "id": "3", "state": "post", "completed": \(completed) } },
            "competitors": [
              { "id": "h\(id)", "uid": "uh\(id)", "type": "team", "order": 0, "homeAway": "home", "score": "\(homeScore)",
                "team": { "id": "h\(id)", "uid": "th\(id)", "displayName": "\(home)", "shortDisplayName": "\(home)", "isActive": true, "links": [] } },
              { "id": "a\(id)", "uid": "ua\(id)", "type": "team", "order": 1, "homeAway": "away", "score": "\(awayScore)",
                "team": { "id": "a\(id)", "uid": "ta\(id)", "displayName": "\(away)", "shortDisplayName": "\(away)", "isActive": true, "links": [] } }
            ]
          }]
        }
        """
    }

    private static var scoreboardJSON: Data {
        let groupEvent = event(id: "1", note: "Group A", home: "Qatar", away: "Ecuador", homeScore: "0", awayScore: "2", completed: true, seasonType: 1)
        let r16 = event(id: "2", note: "Round of 16", home: "Brazil", away: "Croatia", homeScore: "2", awayScore: "1", completed: true)
        let final = event(id: "3", note: "Final", home: "Argentina", away: "France", homeScore: "0", awayScore: "0", completed: false)
        let third = event(id: "4", note: "Third Place", home: "Morocco", away: "Croatia", homeScore: "1", awayScore: "2", completed: true)
        let json = """
        { "leagues": [], "events": [\(groupEvent), \(r16), \(final), \(third)] }
        """
        return Data(json.utf8)
    }
}
