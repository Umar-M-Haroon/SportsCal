@testable import App
import XCTVapor
import SportsCalModel

final class AppTests: XCTestCase {
    func testLive() async throws {
        let app = Application(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        try await configure(app)

        try app.test(.GET, "live", afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
        })
    }
    func testTeams() async throws {
        let app = Application(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        try await configure(app)

        let decoder = JSONDecoder()
        try app.test(.GET, "teams", afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let _ = try res.content.decode([Team].self, using: decoder)
        })
    }

    func testNumberOfTeams() async throws {
        let app = Application(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        try await configure(app)
        //897 teams
        let decoder = JSONDecoder()
        try app.test(.GET, "teams-by-league", afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let espnTeams = try res.content.decode([Leagues: TeamResponse].self, using: decoder)
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
            try await configure(app)
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

                        let foundHomeTeam = self.getTeamInfoFrom(teams: teams, teamID: idHomeTeam) ?? self.getTeamInfoFrom(teams: teams, teamName: strHomeTeam) ?? self.getTeamInfoFrom(teamDict: teamDictID, teamID: idHomeTeam) ?? self.getTeamInfoFrom(teamDict: teamDictName, teamName: strHomeTeam)
                        let foundAwayTeam = self.getTeamInfoFrom(teams: teams, teamID: idAwayTeam) ?? self.getTeamInfoFrom(teams: teams, teamName: strAwayTeam) ?? self.getTeamInfoFrom(teamDict: teamDictID, teamID: idAwayTeam) ?? self.getTeamInfoFrom(teamDict: teamDictName, teamName: strAwayTeam)

                        let foundTeam = foundHomeTeam == nil && foundAwayTeam == nil

                        return foundTeam
                    }
                    print(gamesWithoutCode.count)
                    XCTAssertEqual(gamesWithoutCode.count, 334)
                    defer { Task { try? await app.asyncShutdown() } }
                })
            })
        } catch {
            print(error.localizedDescription)
        }
    }

    func testLiveGames() async throws {
        let app = Application(.development)
        try await configure(app)
        var directory = app.directory.workingDirectory
        directory.append("/LiveTest.json")
        let _ = JSONDecoder()
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
    // Precise game count tests have been moved to ScheduleCountTests.swift
}
