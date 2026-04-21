//
//  SportsCalTests.swift
//  SportsCalTests
//
//  Created by Umar Haroon on 3/24/23.
//

import XCTest
import SportsCalModel
@testable import Scoreline
final class SportsCalTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // MARK: - Helpers

    private func games(in events: [Game], forLeague league: Leagues) -> [Game] {
        events.filter { $0.idLeague == "\(league.rawValue)" }
    }

    func testStableLeagueGameCounts() async throws {
        let result: LiveScore
        do {
            result = try await NetworkHandler.handleCall(debug: true)
        } catch {
            throw XCTSkip("Network unavailable: \(error.localizedDescription)")
        }

        let allSportEvents: [(LiveEvent?, String)] = [
            (result.nba, "NBA"), (result.nfl, "NFL"), (result.nhl, "NHL"),
            (result.mlb, "MLB"), (result.soccer, "Soccer"),
            (result.golf, "Golf"), (result.tennis, "Tennis"), (result.racing, "Racing")
        ]

        // Collect all valid games
        let allEvents = allSportEvents.compactMap { $0.0 }.flatMap { $0.events }
        let validGames = allEvents.filter { game in
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let _ = Leagues(rawValue: intLeague) else { return false }
            return true
        }

        let month = Calendar.current.component(.month, from: Date())

        // API returns multi-season data (current + previous season)

        // NBA (Oct–Jun): 2 seasons regular + playoffs
        if (10...12).contains(month) || (1...6).contains(month) {
            let nba = games(in: validGames, forLeague: .nba)
            XCTAssertGreaterThanOrEqual(nba.count, 2400, "NBA should have ≥2400 games (2 seasons), got \(nba.count)")
            XCTAssertLessThanOrEqual(nba.count, 2800, "NBA should have ≤2800 games, got \(nba.count)")
        }

        // NHL (Oct–Jun): 2 seasons regular + playoffs
        if (10...12).contains(month) || (1...6).contains(month) {
            let nhl = games(in: validGames, forLeague: .nhl)
            XCTAssertGreaterThanOrEqual(nhl.count, 2600, "NHL should have ≥2600 games (2 seasons), got \(nhl.count)")
            XCTAssertLessThanOrEqual(nhl.count, 3100, "NHL should have ≤3100 games, got \(nhl.count)")
        }

        // MLB (Apr–Oct): early season has fewer games, full season ramps up
        if (4...10).contains(month) {
            let mlb = games(in: validGames, forLeague: .mlb)
            // Early April may have very few games as the season just started
            if month >= 5 {
                XCTAssertGreaterThanOrEqual(mlb.count, 2400, "MLB should have ≥2400 games after April, got \(mlb.count)")
            } else {
                XCTAssertGreaterThan(mlb.count, 0, "MLB should have some games in April, got \(mlb.count)")
            }
        }

        // NFL (Sep–Feb): multi-season
        if (9...12).contains(month) || (1...2).contains(month) {
            let nfl = games(in: validGames, forLeague: .nfl)
            XCTAssertGreaterThanOrEqual(nfl.count, 272, "NFL should have ≥272 games, got \(nfl.count)")
        }

        // Soccer domestic leagues (Aug–May): 2 seasons
        if (8...12).contains(month) || (1...5).contains(month) {
            let epl = games(in: validGames, forLeague: .English_Premier_League)
            XCTAssertGreaterThanOrEqual(epl.count, 760, "EPL should have ≥760 games (2×380), got \(epl.count)")

            let laLiga = games(in: validGames, forLeague: .La_Liga)
            XCTAssertGreaterThanOrEqual(laLiga.count, 760, "La Liga should have ≥760 games (2×380), got \(laLiga.count)")

            let serieA = games(in: validGames, forLeague: .Serie_A)
            XCTAssertGreaterThanOrEqual(serieA.count, 760, "Serie A should have ≥760 games (2×380), got \(serieA.count)")

            let bundesliga = games(in: validGames, forLeague: .German_Bundesliga)
            XCTAssertGreaterThanOrEqual(bundesliga.count, 612, "Bundesliga should have ≥612 games (2×306), got \(bundesliga.count)")

            let ligue1 = games(in: validGames, forLeague: .Ligue_1)
            XCTAssertGreaterThanOrEqual(ligue1.count, 612, "Ligue 1 should have ≥612 games (2×306), got \(ligue1.count)")

            let eredivisie = games(in: validGames, forLeague: .Eredivisie)
            XCTAssertGreaterThanOrEqual(eredivisie.count, 612, "Eredivisie should have ≥612 games (2×306), got \(eredivisie.count)")
        }

        // F1: 2 seasons
        if let racingEvents = result.racing?.events {
            let f1 = games(in: racingEvents, forLeague: .formula1)
            XCTAssertGreaterThanOrEqual(f1.count, 22, "F1 should have ≥22 events, got \(f1.count)")
            XCTAssertLessThanOrEqual(f1.count, 50, "F1 should have ≤50 events, got \(f1.count)")
        }

        // PGA: multi-season tournaments
        if let golfEvents = result.golf?.events {
            let pga = games(in: golfEvents, forLeague: .pga)
            XCTAssertGreaterThanOrEqual(pga.count, 80, "PGA should have ≥80 events, got \(pga.count)")
            XCTAssertLessThanOrEqual(pga.count, 300, "PGA should have ≤300 events, got \(pga.count)")
        }

        // Tennis: individual matches (counts vary by time of year)
        if let tennisEvents = result.tennis?.events {
            let atp = games(in: tennisEvents, forLeague: .atp)
            XCTAssertGreaterThanOrEqual(atp.count, 5000, "ATP should have ≥5000 matches, got \(atp.count)")

            let wta = games(in: tennisEvents, forLeague: .wta)
            XCTAssertGreaterThanOrEqual(wta.count, 5000, "WTA should have ≥5000 matches, got \(wta.count)")
        }
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
