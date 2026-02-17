import XCTest
@testable import SportsCalModel

final class SportsCalModelTests: XCTestCase {
    func testLoadingScoreboards() throws {
        XCTAssertNoThrow(try JSONLoader.load(file: "BasketballScoreboard", type: Scoreboard.self))
        XCTAssertNoThrow(try JSONLoader.load(file: "BasketballScoreboardCurrentlyPlaying", type: Scoreboard.self))
        XCTAssertNoThrow(try JSONLoader.load(file: "NHLScoreboard", type: Scoreboard.self))
        XCTAssertNoThrow(try JSONLoader.load(file: "NFLScoreboard", type: Scoreboard.self))
        XCTAssertNoThrow(try JSONLoader.load(file: "MLBScoreboard", type: Scoreboard.self))
        XCTAssertNoThrow(try JSONLoader.load(file: "BasketballScoreboardMultipleDates", type: Scoreboard.self))
    }
    
    func testLoadingTeams() throws {
        let nbaTeams: TeamResponse? = try JSONLoader.load(file: "NBATeams", type: TeamResponse.self) as? TeamResponse
        XCTAssertNoThrow(try JSONLoader.load(file: "NBATeams", type: TeamResponse.self))
        XCTAssertNoThrow(try JSONLoader.load(file: "NFLTeams", type: TeamResponse.self))
        XCTAssertNoThrow(try JSONLoader.load(file: "NHLTeams", type: TeamResponse.self))
        XCTAssertNoThrow(try JSONLoader.load(file: "MLBTeams", type: TeamResponse.self))
        XCTAssertNoThrow(try JSONLoader.load(file: "CurrentTeamsTSDB", type: [Team].self))
    }
    
    func testNumberTeams() throws {
        let nbaTeams: TeamResponse? = try JSONLoader.load(file: "NBATeams", type: TeamResponse.self) as? TeamResponse
        XCTAssertEqual(nbaTeams?.teams?.count, 30)
        let nflTeams: TeamResponse? = try JSONLoader.load(file: "NFLTeams", type: TeamResponse.self) as? TeamResponse
        XCTAssertEqual(nflTeams?.teams?.count, 32)
    }
    
    func testConvertingTeams() throws {
        let api2Scoreboard: Scoreboard = try XCTUnwrap(try JSONLoader.load(file: "BasketballScoreboardCurrentlyPlaying", type: Scoreboard.self) as? Scoreboard)
        let TSDBLive: LiveScore? = try JSONLoader.load(file: "TSDBLive", type: LiveScore.self) as? LiveScore
        XCTAssertNotNil(TSDBLive)
        XCTAssertEqual(api2Scoreboard.events.count, 10)
        XCTAssertEqual(TSDBLive?.nba?.events.count, 7)
        var foundGames = 0
        let liveEvents = LiveEvent(events: api2Scoreboard, league: .nba)
        if let events = TSDBLive?.nba?.events {
            for event in events {
                if let foundEvent = liveEvents?.events.first(where: {$0.strHomeTeam == event.strHomeTeam && $0.strAwayTeam == event.strAwayTeam}) {
                    foundGames += 1
                    print(foundEvent)
                }
            }
        }
        XCTAssertEqual(foundGames, 7)
    }
    
    func testLoadingStandings() throws {}
    
    func testConverter() throws {
        
    }
    
    @available(macOS 13, *)
    func testScoreboardFetching() throws {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.timeZone = .init(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"

        let date = calendar.date(from: .init(calendar: calendar, timeZone: .gmt, year: 2023, month: 03, day: 11, hour: 12, minute: 29, second: 0))!
        let prem: Scoreboard = try XCTUnwrap(try JSONLoader.load(file: "Premier-League-Scoreboard", type: Scoreboard.self) as? Scoreboard)
        let events = prem.events.contains(where: { game in
            guard let gameDate = formatter.date(from: game.date) else { return false }
            let components = calendar.dateComponents([.day, .hour, .month, .year, .minute], from: date, to: gameDate)
            let isValidTime = components.day ?? -1 == 0 &&
            components.hour ?? -1 == 0 &&
            components.month ?? -1 == 0 &&
            components.year ?? -1 == 0 &&
            components.minute ?? -1 <= 1
            return isValidTime
        })
        XCTAssertTrue(events)
    }
    
    func testScoreboardCompletedGames() throws {
        
        let scoreboard = try XCTUnwrap(try JSONLoader.load(file: "NBAScoreboardWithCompletedGames", type: Scoreboard.self) as? Scoreboard)
        let live = LiveEvent(events: scoreboard, league: .nba)
        let completed = (live?.events.filter({$0.isCompleted == true }))
        XCTAssertEqual(completed?.count, 1)
    }
}
