//
//  SportsCalTests.swift
//  SportsCalTests
//
//  Created by Umar Haroon on 3/24/23.
//

import XCTest
import SportsCalModel
@testable import SportsCal
final class SportsCalTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() async throws {
        let result = try await NetworkHandler.handleCall(debug: true)
                var totalGames = [result.nhl?.events, result.nfl?.events, result.soccer?.events, result.mlb?.events, result.nba?.events]
                    .compactMap({$0})
                    .flatMap({$0})
                totalGames = totalGames.filter({ game in
                    guard let leagueString = game.idLeague,
                          let intLeague = Int(leagueString),
                          let _ = Leagues(rawValue: intLeague) else {
                        return false
                    }
                    return true
                })
                let gamesDict = Dictionary(grouping: totalGames, by: { game in
                    SportType(league: Leagues.init(rawValue: Int(game.idLeague!)!)!)
                })
        let ligaGames = gamesDict[.soccer]?.filter({ game in
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let league = Leagues(rawValue: intLeague),
                  league == .La_Liga else { return false }
            return true
        })
        XCTAssertEqual(ligaGames?.count, 380)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            let model = GameViewModel(appStorage: .init(), favorites: .init())
            model.sortedGames.count
            // Put the code you want to measure the time of here.
        }
    }

}
