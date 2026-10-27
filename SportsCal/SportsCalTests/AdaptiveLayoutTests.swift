import XCTest
import SportsCalModel
@testable import Scoreline

/// Pins the width breakpoints that pick the Games layout, and the calendar's
/// day grouping shared by its sheet and its inline day column.
///
/// The breakpoints matter on the iPhone Duo: its inner display reports a regular
/// size class at only 669–951pt, so the old size-class switch put it on the iPad
/// board. These widths are the real panel sizes in points.
final class AdaptiveLayoutTests: XCTestCase {

    // MARK: - Games layout

    func testPhonesAndTheDuoOuterDisplayGetTheList() {
        XCTAssertEqual(GamesLayout(width: 402), .list)   // iPhone 18 Pro
        XCTAssertEqual(GamesLayout(width: 466), .list)   // Duo outer, portrait
        XCTAssertEqual(GamesLayout(width: 669), .list)   // Duo inner, portrait
        XCTAssertEqual(GamesLayout(width: 719), .list)
    }

    func testTheUnfoldedDuoInLandscapeGetsListBesideDetail() {
        XCTAssertEqual(GamesLayout(width: 720), .split)
        XCTAssertEqual(GamesLayout(width: 744), .split)  // iPad mini portrait
        XCTAssertEqual(GamesLayout(width: 834), .split)  // iPad Air portrait
        XCTAssertEqual(GamesLayout(width: 951), .split)  // Duo inner, landscape
    }

    func testWideWindowsKeepTheBoard() {
        XCTAssertEqual(GamesLayout(width: 1100), .board)
        XCTAssertEqual(GamesLayout(width: 1180), .board) // iPad Air landscape
    }

    // MARK: - Fold state

    func testHalfFoldedAcrossNeedsAPartiallyOpenHingeAndAHorizontalFold() {
        let across = CGRect(x: 0, y: 470, width: 669, height: 12)
        let down = CGRect(x: 470, y: 0, width: 12, height: 669)

        XCTAssertTrue(FoldState(hinge: .partiallyOpen, division: across).isHalfFoldedAcross)
        XCTAssertFalse(FoldState(hinge: .partiallyOpen, division: down).isHalfFoldedAcross)
        XCTAssertFalse(FoldState(hinge: .fullyOpen, division: across).isHalfFoldedAcross)
        XCTAssertFalse(FoldState(hinge: .partiallyOpen, division: nil).isHalfFoldedAcross)
        XCTAssertFalse(FoldState().isHalfFoldedAcross)
    }

    // MARK: - Calendar day

    func testCalendarDayKeepsOnlyThatDaysGames() throws {
        let calendar = Calendar.current
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12)))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))

        let onDay = game("on-day", at: day)
        let otherDay = game("next-day", at: nextDay)
        let components = calendar.dateComponents([.year, .month, .day], from: day)

        let result = CalendarDayGames(day: components, games: [onDay, otherDay], liveGames: [otherDay])

        XCTAssertEqual(result.listGames.flatMap(\.value).map(\.id), [onDay.id])
        XCTAssertTrue(result.liveGames.isEmpty)
    }

    private func game(_ id: String, at date: Date) -> Game {
        Game(
            idEvent: id, idLeague: "\(Leagues.nba.rawValue)",
            strHomeTeam: "Home \(id)", strAwayTeam: "Away \(id)",
            isoDate: date
        )
    }
}
