//
//  ScheduleSliceSyncTests.swift
//  SportsCalTests
//

import XCTest
import SportsCalModel
@testable import Scoreline

final class ScheduleSliceSyncTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "ScheduleSliceSyncTests")
        defaults.removePersistentDomain(forName: "ScheduleSliceSyncTests")
    }

    func testOnlyEnabledSportsPlusMeta() {
        let keys = ScheduleSliceSync.wantedKeys(sports: [.basketball, .nfl], college: false, motorsport: false, favoriteKeys: [])
        XCTAssertEqual(keys, [.nba, .nfl, .meta])
    }

    func testCollegeAndMotorsportFollowTheirSwitches() {
        let keys = ScheduleSliceSync.wantedKeys(sports: [.nfl, .racing], college: true, motorsport: true, favoriteKeys: [])
        XCTAssertEqual(keys, [.nfl, .ncaaf, .racing, .motorsport, .meta])
    }

    func testFollowedTeamsSportIsKeptWhenOff() {
        let keys = ScheduleSliceSync.wantedKeys(sports: [.basketball], college: false, motorsport: false, favoriteKeys: [.soccer])
        XCTAssertEqual(keys, [.nba, .soccer, .meta])
    }

    func testNothingOnFetchesEverything() {
        XCTAssertEqual(ScheduleSliceSync.wantedKeys(sports: [], college: false, motorsport: false, favoriteKeys: []),
                       LiveScore.WireKey.allCases)
    }

    func testEnabledSportsFromDefaults() {
        defaults.set(true, forKey: "shouldShowWNBA")
        defaults.set(true, forKey: "shouldShowWorldCup")
        defaults.set(true, forKey: "shouldShowCFB")
        XCTAssertEqual(ScheduleSliceSync.enabledSports(defaults: defaults), [.basketball, .soccer, .nfl],
                       "WNBA rides with the NBA, the World Cup with soccer, college with football")
    }

    func testFavoriteSlicesAreRememberedAndKeptWhenAbsent() {
        let arsenal = Game(idEvent: "1", idLeague: "4328", strHomeTeam: "Arsenal", strAwayTeam: "Chelsea", isoDate: nil)
        let lakers = Game(idEvent: "2", idLeague: "4387", strHomeTeam: "Lakers", strAwayTeam: "Celtics", isoDate: nil)
        let all = LiveScore(nba: LiveEvent(events: [lakers]), soccer: LiveEvent(events: [arsenal]))
        FavoriteSlices.update(from: all, isFavorite: { $0.strHomeTeam == "Arsenal" }, defaults: defaults)
        XCTAssertEqual(FavoriteSlices.keys(defaults: defaults), [.soccer])

        // A later slice-based snapshot without soccer (sport off) must not forget it.
        let nbaOnly = LiveScore(nba: LiveEvent(events: [lakers]))
        FavoriteSlices.update(from: nbaOnly, isFavorite: { $0.strHomeTeam == "Arsenal" }, defaults: defaults)
        XCTAssertEqual(FavoriteSlices.keys(defaults: defaults), [.soccer])
    }
}
