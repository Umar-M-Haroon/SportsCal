import XCTest
@testable import SportsCalModel

/// Per-widget tour picks: the schedule widget's league pick and the golf leaderboard's tour.
final class WidgetTourFilterTests: XCTestCase {

    private func golf(_ name: String, tour: Leagues, ts: String = "2026-09-24T12:00Z",
                      leaderboard: Bool = false, status: String? = nil) -> Game {
        Game(idEvent: name, idLeague: "\(tour.rawValue)", strHomeTeam: name, strAwayTeam: "Leader",
             strStatus: status, strTimestamp: ts, isoDate: nil,
             leaderboardEntries: leaderboard ? [LeaderboardEntry(name: "A", score: "-5", position: 1)] : nil)
    }

    private func tennis(_ id: String, board: Leagues, draw: String?) -> Game {
        Game(idEvent: id, idLeague: "\(board.rawValue)", idHomeTeam: "1", idAwayTeam: "2",
             strHomeTeam: "Home \(id)", strAwayTeam: "Away \(id)", strTimestamp: "2026-09-24T12:00Z",
             isoDate: nil, tournamentName: "Open", drawSlug: draw)
    }

    private func soccer(_ league: Leagues) -> Game {
        Game(idEvent: "s\(league.rawValue)", idLeague: "\(league.rawValue)", idHomeTeam: "1", idAwayTeam: "2",
             strHomeTeam: "H", strAwayTeam: "A", strTimestamp: "2026-09-24T12:00Z", isoDate: nil)
    }

    // MARK: - League picks

    func testNoPickFallsBackToApp() {
        XCTAssertNil(WidgetTourFilter.hiddenLeagueNames(selected: []))
    }

    /// Existing widgets that picked a soccer league keep hiding tennis, and don't start
    /// hiding golf because golf tours joined the picker.
    func testLegacySoccerPickLeavesGolfAlone() throws {
        let hidden = try XCTUnwrap(WidgetTourFilter.hiddenLeagueNames(selected: [.English_Premier_League]))
        XCTAssertFalse(hidden.contains(Leagues.English_Premier_League.leagueName))
        XCTAssertTrue(hidden.contains(Leagues.atp.leagueName))
        XCTAssertTrue(hidden.contains(Leagues.La_Liga.leagueName))
        for tour in Leagues.allCases where tour.isGolf {
            XCTAssertFalse(hidden.contains(tour.leagueName), "\(tour) must not be hidden by a soccer pick")
        }
    }

    func testGolfPickNarrowsGolf() throws {
        let hidden = try XCTUnwrap(WidgetTourFilter.hiddenLeagueNames(selected: [.lpga]))
        XCTAssertFalse(hidden.contains(Leagues.lpga.leagueName))
        XCTAssertTrue(hidden.contains(Leagues.pga.leagueName))
        XCTAssertTrue(hidden.contains(Leagues.dpWorld.leagueName))
    }

    func testATPOnlyGoesByDrawNotBoard() throws {
        let hidden = try XCTUnwrap(WidgetTourFilter.hiddenLeagueNames(selected: [.atp]))
        let games = [
            tennis("1", board: .atp, draw: "mens-singles"),
            tennis("2", board: .atp, draw: "womens-singles"),   // cached under the wrong board
            tennis("3", board: .wta, draw: "mixed-doubles"),
            tennis("4", board: .wta, draw: nil),                // no draw: board decides
            soccer(.English_Premier_League),
        ]
        let kept = WidgetTourFilter.filter(games, hidingLeagues: hidden).map(\.idEvent)
        XCTAssertEqual(kept, ["1", "3"])
    }

    func testWTAOnly() throws {
        let hidden = try XCTUnwrap(WidgetTourFilter.hiddenLeagueNames(selected: [.wta]))
        let games = [
            tennis("1", board: .atp, draw: "mens-singles"),
            tennis("2", board: .atp, draw: "womens-singles"),
            tennis("4", board: .wta, draw: nil),
        ]
        XCTAssertEqual(WidgetTourFilter.filter(games, hidingLeagues: hidden).map(\.idEvent), ["2", "4"])
    }

    /// A match shipped once per tour board shows once.
    func testDuplicateTennisRowsCollapse() {
        let games = [
            tennis("9", board: .atp, draw: "mens-singles"),
            tennis("9", board: .wta, draw: "mens-singles"),
        ]
        XCTAssertEqual(WidgetTourFilter.filter(games, hidingLeagues: []).count, 1)
    }

    /// With no draw the board decides, so a hidden first copy must not swallow the
    /// visible second one.
    func testDuplicateWithoutDrawKeepsVisibleCopy() throws {
        let hidden = try XCTUnwrap(WidgetTourFilter.hiddenLeagueNames(selected: [.wta]))
        let games = [
            tennis("9", board: .atp, draw: nil),
            tennis("9", board: .wta, draw: nil),
        ]
        let kept = WidgetTourFilter.filter(games, hidingLeagues: hidden)
        XCTAssertEqual(kept.map(\.idLeague), ["\(Leagues.wta.rawValue)"])
    }

    func testAppHiddenCompetitionsStillApply() {
        let games = [soccer(.English_Premier_League), soccer(.La_Liga), golf("Open", tour: .pga)]
        let kept = WidgetTourFilter.filter(games, hidingLeagues: [Leagues.La_Liga.leagueName])
        XCTAssertEqual(kept.map(\.idLeague), ["\(Leagues.English_Premier_League.rawValue)", "\(Leagues.pga.rawValue)"])
    }

    // MARK: - Golf leaderboard

    func testAllToursFeaturesBiggestLiveEvent() {
        let events = [
            golf("Korn Ferry Event", tour: .kornFerry, leaderboard: true),
            golf("PGA Championship", tour: .pga, leaderboard: true),
            golf("LPGA Event", tour: .lpga, leaderboard: true),
        ]
        XCTAssertEqual(WidgetTourFilter.featuredLiveGolfEvent(events, tour: nil)?.strHomeTeam, "PGA Championship")
    }

    func testPickedTourFeaturesItsOwnLiveEvent() {
        let events = [
            golf("PGA Championship", tour: .pga, leaderboard: true),
            golf("LPGA Event", tour: .lpga, leaderboard: true),
            golf("LIV Event", tour: .livGolf, leaderboard: false),
        ]
        XCTAssertEqual(WidgetTourFilter.featuredLiveGolfEvent(events, tour: .lpga)?.strHomeTeam, "LPGA Event")
        // A tour with nothing live yields nil so the caller falls back to the schedule.
        XCTAssertNil(WidgetTourFilter.featuredLiveGolfEvent(events, tour: .livGolf))
    }

    func testScheduledEventIsNextOnPickedTour() {
        let games = [
            golf("PGA Next", tour: .pga, ts: "2026-09-25T12:00Z"),
            golf("DP Later", tour: .dpWorld, ts: "2026-10-02T12:00Z"),
            golf("DP Cancelled", tour: .dpWorld, ts: "2026-09-26T12:00Z", status: "Cancelled"),
            golf("DP Soon", tour: .dpWorld, ts: "2026-09-27T12:00Z"),
            soccer(.English_Premier_League),
        ]
        XCTAssertEqual(WidgetTourFilter.scheduledGolfEvent(games, tour: .dpWorld)?.strHomeTeam, "DP Soon")
        XCTAssertEqual(WidgetTourFilter.scheduledGolfEvent(games, tour: nil)?.strHomeTeam, "PGA Next")
        XCTAssertNil(WidgetTourFilter.scheduledGolfEvent(games, tour: .lpga))
    }
}
