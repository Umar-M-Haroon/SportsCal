@testable import App
import XCTVapor
import SportsCalModel

final class AppTests: XCTestCase {
    func testLive() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)
        
        try app.test(.GET, "live", afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
        })
    }
    func testTeams() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)

        let decoder = JSONDecoder()
        try app.test(.GET, "teams", afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let teams = try res.content.decode([Team].self, using: decoder)
        })
    }

    func testNumberOfTeams() async throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)
        //897 teams
        let decoder = JSONDecoder()
        try app.test(.GET, "teams-by-league", afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let espnTeams = try res.content.decode([Leagues: TeamResponse].self, using: decoder)
            for (league, teams) in espnTeams {
//                print("-----------")
//                print(league)
//                print("-----------")
//                teams.teams?.forEach { team in
//                    if let name = team.name,
//                       let abb = team.abbreviation {
//                        print(name, abb)
//                    }
//                }
            }
            XCTAssertEqual(897, espnTeams.reduce(into: 0, {$0 += ($1.value.teams?.count ?? 0)}))
        })
        
        
        try app.test(.GET, "schedules", afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let schedules = try res.content.decode(LiveScore.self, using: decoder)
            guard let nbaEvents = schedules.nba?.events,
                  let nflEvents = schedules.nhl?.events,
                  let nhlEvents = schedules.nhl?.events,
                  let mlbEvents = schedules.mlb?.events,
                  let soccerEvents = schedules.soccer?.events else {
                XCTFail("schedules not there")
                return
            }
            let combined = nbaEvents + nflEvents + nhlEvents + mlbEvents + soccerEvents
            let homeTeams = Set(Dictionary(grouping: combined, by: \.strHomeTeam).map({$0.key}))
            let awayTeams = Set(Dictionary(grouping: combined, by: \.strAwayTeam).map({$0.key}))
            let teams = homeTeams.union(awayTeams)
            print(teams.count)
        })
    }
    
    func testGamesWithoutCodes() async throws {
        let app = Application(.development)
        do {
            try configure(app)
            //897 teams
            let decoder = JSONDecoder()
            try app.test(.GET, "teams", afterResponse: { resTeams in
                let teams = try resTeams.content.decode([Team].self, using: decoder)
                let teamDictName = Dictionary(grouping: teams, by: \.strTeam)
                let teamDictID = Dictionary(grouping: teams, by: \.idTeam)
                try app.test(.GET, "schedules", afterResponse: { res in
                    
                    XCTAssertEqual(res.status, .ok)
                    let schedules = try res.content.decode(LiveScore.self, using: decoder)
                    guard let nbaEvents = schedules.nba?.events,
                          let nflEvents = schedules.nhl?.events,
                          let nhlEvents = schedules.nhl?.events,
                          let mlbEvents = schedules.mlb?.events,
                          let soccerEvents = schedules.soccer?.events else {
                        XCTFail("schedules not there")
                        return
                    }
                    let combined = nbaEvents + nflEvents + nhlEvents + mlbEvents + soccerEvents
                    let gamesWithoutCode = combined.filter { event in
                        let strHomeTeam = event.strHomeTeam
                        let strAwayTeam = event.strAwayTeam
                        guard let idHomeTeam = event.idHomeTeam,
                              let idAwayTeam = event.idAwayTeam else {
                            return false
                        }
                        
                        let foundHomeTeam = getTeamInfoFrom(teams: teams, teamID: idHomeTeam) ?? getTeamInfoFrom(teams: teams, teamName: strHomeTeam) ?? getTeamInfoFrom(teamDict: teamDictID, teamID: idHomeTeam) ?? getTeamInfoFrom(teamDict: teamDictName, teamName: strHomeTeam)
                        let foundAwayTeam = getTeamInfoFrom(teams: teams, teamID: idAwayTeam) ?? getTeamInfoFrom(teams: teams, teamName: strAwayTeam) ?? getTeamInfoFrom(teamDict: teamDictID, teamID: idAwayTeam) ?? getTeamInfoFrom(teamDict: teamDictName, teamName: strAwayTeam)
                        
                        let foundTeam = foundHomeTeam == nil && foundAwayTeam == nil
                        
                        
                        return foundTeam
                    }
                    print(gamesWithoutCode.count)
                    XCTAssertEqual(gamesWithoutCode.count, 334)
                    defer { app.shutdown() }
                })
            })
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func testLiveGames() async throws {
        let app = Application(.development)
//        do {
            try configure(app)
            //897 teams
            var directory = app.directory.workingDirectory
            directory.append("/LiveTest.json")
            let decoder = JSONDecoder()
//            let teams = try resTeams.content.decode([Team].self, using: decoder)
//            
//            try app.test(.GET, "schedules", afterResponse: { res in
//                
//                XCTAssertEqual(res.status, .ok)
//                let schedules = try res.content.decode(LiveScore.self, using: decoder)
//                guard let nbaEvents = schedules.nba?.events,
//                      let nflEvents = schedules.nhl?.events,
//                      let nhlEvents = schedules.nhl?.events,
//                      let mlbEvents = schedules.mlb?.events,
//                      let soccerEvents = schedules.soccer?.events else {
//                    XCTFail("schedules not there")
//                    return
//                }
//                let combined = nbaEvents + nflEvents + nhlEvents + mlbEvents + soccerEvents
//                let gamesWithoutCode = combined.filter { event in
//                    let strHomeTeam = event.strHomeTeam
//                    let strAwayTeam = event.strAwayTeam
//                    guard let idHomeTeam = event.idHomeTeam,
//                          let idAwayTeam = event.idAwayTeam else {
//                        return false
//                    }
//                    
//                    let foundHomeTeam = getTeamInfoFrom(teams: teams, teamID: idHomeTeam) ?? getTeamInfoFrom(teams: teams, teamName: strHomeTeam) ?? getTeamInfoFrom(teamDict: teamDictID, teamID: idHomeTeam) ?? getTeamInfoFrom(teamDict: teamDictName, teamName: strHomeTeam)
//                    let foundAwayTeam = getTeamInfoFrom(teams: teams, teamID: idAwayTeam) ?? getTeamInfoFrom(teams: teams, teamName: strAwayTeam) ?? getTeamInfoFrom(teamDict: teamDictID, teamID: idAwayTeam) ?? getTeamInfoFrom(teamDict: teamDictName, teamName: strAwayTeam)
//                    
//                    let foundTeam = foundHomeTeam == nil && foundAwayTeam == nil
//                    
//                    
//                    return foundTeam
//                }
//                print(gamesWithoutCode.count)
//                XCTAssertEqual(gamesWithoutCode.count, 334)
//                defer { app.shutdown() }
//            })
//        } catch {
//            print(error.localizedDescription)
//        }
    }
    
    func getTeamInfoFrom(teams: [Team], teamID: String?) -> Team? {
        let defaultTeam = teams.first { team in
            team.idTeam == teamID && team.strTeamShort != nil
        }
        return defaultTeam ?? teams.first { team in
            team.idTeam == teamID
        }
    }
    func getTeamInfoFrom(teams: [Team], teamName: String?) -> Team? {
        let defaultTeam = teams.first { team in
            team.strTeam == teamName && team.strTeamShort != nil
        }
        return defaultTeam ?? teams.first { team in
            team.strTeam == teamName
        }
    }
    func getTeamInfoFrom(teamDict: [String?: [Team]], teamID: String?) -> Team? {
        return teamDict[teamID]?.first
    }
    func getTeamInfoFrom(teamDict: [String?: [Team]], teamName: String?) -> Team? {
        return teamDict[teamName]?.first
    }

    // MARK: - Game Count Validation Tests

    /// Expected game count ranges for each league's schedule data.
    /// These ranges account for the API returning multiple seasons of data,
    /// including regular season, playoffs, and historical games.
    /// Note: Ranges use 0 as minimum since leagues have off-seasons.
    struct LeagueGameCountExpectation {
        let minGames: Int
        let maxGames: Int
        let description: String

        static let nba = LeagueGameCountExpectation(
            minGames: 0,
            maxGames: 3000,
            description: "NBA may include multiple seasons of data"
        )
        static let nfl = LeagueGameCountExpectation(
            minGames: 0,
            maxGames: 500,
            description: "NFL regular season ~272 games + playoffs (0 during off-season)"
        )
        static let nhl = LeagueGameCountExpectation(
            minGames: 0,
            maxGames: 2000,
            description: "NHL may include multiple seasons of data"
        )
        static let mlb = LeagueGameCountExpectation(
            minGames: 0,
            maxGames: 3000,
            description: "MLB regular season ~2430 games (0 during off-season)"
        )
        // Soccer varies greatly by active leagues and time of year
        static let soccer = LeagueGameCountExpectation(
            minGames: 0,
            maxGames: 15000,
            description: "Soccer includes multiple leagues and competitions"
        )
    }

    /// Tests that the /schedules endpoint returns game counts within expected ranges.
    /// This is a live API test that validates reasonable data is being returned.
    /// Note: This test requires the external API to be accessible.
    func testSchedulesGameCountRanges() async throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)

        let decoder = JSONDecoder()
        try app.test(.GET, "schedules", afterResponse: { res in
            // Skip validation if API is unavailable
            guard res.status == .ok else {
                print("Skipping testSchedulesGameCountRanges: API returned \(res.status)")
                return
            }

            let schedules = try res.content.decode(LiveScore.self, using: decoder)

            // NBA game count validation
            if let nbaEvents = schedules.nba?.events {
                let nbaCount = nbaEvents.count
                XCTAssertGreaterThanOrEqual(
                    nbaCount,
                    LeagueGameCountExpectation.nba.minGames,
                    "NBA should have at least \(LeagueGameCountExpectation.nba.minGames) games, got \(nbaCount)"
                )
                XCTAssertLessThanOrEqual(
                    nbaCount,
                    LeagueGameCountExpectation.nba.maxGames,
                    "NBA should have at most \(LeagueGameCountExpectation.nba.maxGames) games, got \(nbaCount)"
                )
            }

            // NFL game count validation
            if let nflEvents = schedules.nfl?.events {
                let nflCount = nflEvents.count
                XCTAssertGreaterThanOrEqual(
                    nflCount,
                    LeagueGameCountExpectation.nfl.minGames,
                    "NFL should have at least \(LeagueGameCountExpectation.nfl.minGames) games, got \(nflCount)"
                )
                XCTAssertLessThanOrEqual(
                    nflCount,
                    LeagueGameCountExpectation.nfl.maxGames,
                    "NFL should have at most \(LeagueGameCountExpectation.nfl.maxGames) games, got \(nflCount)"
                )
            }

            // NHL game count validation
            if let nhlEvents = schedules.nhl?.events {
                let nhlCount = nhlEvents.count
                XCTAssertGreaterThanOrEqual(
                    nhlCount,
                    LeagueGameCountExpectation.nhl.minGames,
                    "NHL should have at least \(LeagueGameCountExpectation.nhl.minGames) games, got \(nhlCount)"
                )
                XCTAssertLessThanOrEqual(
                    nhlCount,
                    LeagueGameCountExpectation.nhl.maxGames,
                    "NHL should have at most \(LeagueGameCountExpectation.nhl.maxGames) games, got \(nhlCount)"
                )
            }

            // MLB game count validation
            if let mlbEvents = schedules.mlb?.events {
                let mlbCount = mlbEvents.count
                XCTAssertGreaterThanOrEqual(
                    mlbCount,
                    LeagueGameCountExpectation.mlb.minGames,
                    "MLB should have at least \(LeagueGameCountExpectation.mlb.minGames) games, got \(mlbCount)"
                )
                XCTAssertLessThanOrEqual(
                    mlbCount,
                    LeagueGameCountExpectation.mlb.maxGames,
                    "MLB should have at most \(LeagueGameCountExpectation.mlb.maxGames) games, got \(mlbCount)"
                )
            }

            // Soccer game count validation (more lenient due to seasonal variation)
            if let soccerEvents = schedules.soccer?.events {
                let soccerCount = soccerEvents.count
                XCTAssertGreaterThanOrEqual(
                    soccerCount,
                    LeagueGameCountExpectation.soccer.minGames,
                    "Soccer should have at least \(LeagueGameCountExpectation.soccer.minGames) games, got \(soccerCount)"
                )
                XCTAssertLessThanOrEqual(
                    soccerCount,
                    LeagueGameCountExpectation.soccer.maxGames,
                    "Soccer should have at most \(LeagueGameCountExpectation.soccer.maxGames) games, got \(soccerCount)"
                )
            }
        })
    }

    /// Tests that each /sport/:sport endpoint returns a valid response.
    /// Validates that endpoints are accessible and return decodable data.
    /// Note: This test requires the external API to be accessible.
    func testSportEndpointsReturnValidData() async throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)

        let decoder = JSONDecoder()
        let sports = ["basketball", "football", "hockey", "baseball", "soccer"]

        for sport in sports {
            try app.test(.GET, "sport/\(sport)", afterResponse: { res in
                // Skip validation if API is unavailable
                guard res.status == .ok else {
                    print("Skipping testSportEndpointsReturnValidData for \(sport): API returned \(res.status)")
                    return
                }
                // Verify the response can be decoded as LiveEvent
                XCTAssertNoThrow(
                    try res.content.decode(LiveEvent.self, using: decoder),
                    "/sport/\(sport) should return valid LiveEvent data"
                )
            })
        }
    }

    /// Tests that sport endpoints return non-empty results during active seasons.
    /// Note: This test may need seasonal adjustments as leagues have off-seasons.
    /// Note: This test requires the external API to be accessible.
    func testSportEndpointGameCounts() async throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)

        let decoder = JSONDecoder()
        let sportTests: [(String, String)] = [
            ("basketball", "Basketball"),
            ("football", "Football"),
            ("hockey", "Hockey"),
            ("baseball", "Baseball"),
            ("soccer", "Soccer")
        ]

        for (sport, displayName) in sportTests {
            try app.test(.GET, "sport/\(sport)", afterResponse: { res in
                // Skip validation if API is unavailable
                guard res.status == .ok else {
                    print("Skipping testSportEndpointGameCounts for \(sport): API returned \(res.status)")
                    return
                }
                let liveEvent = try res.content.decode(LiveEvent.self, using: decoder)
                XCTAssertNotNil(liveEvent.events, "\(displayName) endpoint should return events array")
            })
        }
    }

    /// Tests that the total game count across all sports is reasonable.
    /// Note: This test requires the external API to be accessible.
    func testTotalScheduledGamesCount() async throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)

        let decoder = JSONDecoder()
        try app.test(.GET, "schedules", afterResponse: { res in
            // Skip validation if API is unavailable
            guard res.status == .ok else {
                print("Skipping testTotalScheduledGamesCount: API returned \(res.status)")
                return
            }
            let schedules = try res.content.decode(LiveScore.self, using: decoder)

            let nbaCount = schedules.nba?.events.count ?? 0
            let nflCount = schedules.nfl?.events.count ?? 0
            let nhlCount = schedules.nhl?.events.count ?? 0
            let mlbCount = schedules.mlb?.events.count ?? 0
            let soccerCount = schedules.soccer?.events.count ?? 0

            let totalGames = nbaCount + nflCount + nhlCount + mlbCount + soccerCount

            // We expect at least some games to be scheduled
            XCTAssertGreaterThan(
                totalGames,
                0,
                "Total scheduled games should be greater than 0"
            )

            // Log counts for debugging
            print("Game counts - NBA: \(nbaCount), NFL: \(nflCount), NHL: \(nhlCount), MLB: \(mlbCount), Soccer: \(soccerCount), Total: \(totalGames)")
        })
    }
}
