import XCTest
import SportsCalModel
@testable import Scoreline

/// Pins the width and size-class rules that pick the Games and detail layouts,
/// and the calendar's day grouping shared by its sheet and its inline day column.
///
/// The breakpoints matter on the iPhone Duo: its inner display reports a regular
/// size class at only 669–951pt. These widths are the real panel sizes in points.
final class AdaptiveLayoutTests: XCTestCase {

    // MARK: - Games layout

    func testPhonesAndTheDuoOuterDisplayGetTheList() {
        XCTAssertEqual(GamesLayout(width: 402, horizontalSizeClass: .compact, verticalSizeClass: .regular), .list)   // iPhone 18 Pro
        XCTAssertEqual(GamesLayout(width: 466, horizontalSizeClass: .compact, verticalSizeClass: .regular), .list)   // Duo outer, portrait
        // Regular, but too narrow for two board columns (a narrow iPad window).
        XCTAssertEqual(GamesLayout(width: 603, horizontalSizeClass: .regular, verticalSizeClass: .regular), .list)
    }

    func testTheUnfoldedDuoGetsBoardColumnsInBothOrientations() {
        XCTAssertEqual(GamesLayout(width: 604, horizontalSizeClass: .regular, verticalSizeClass: .regular), .board)
        XCTAssertEqual(GamesLayout(width: 669, horizontalSizeClass: .regular, verticalSizeClass: .regular), .board)  // Duo inner, portrait
        XCTAssertEqual(GamesLayout(width: 951, horizontalSizeClass: .regular, verticalSizeClass: .regular), .board)  // Duo inner, landscape
    }

    func testPhonesInLandscapeKeepTheList() {
        // Wide enough for the board, but compact width.
        XCTAssertEqual(GamesLayout(width: 734, horizontalSizeClass: .compact, verticalSizeClass: .compact), .list)
        XCTAssertEqual(GamesLayout(width: 750, horizontalSizeClass: .compact, verticalSizeClass: .compact), .list)
        // Plus / Pro Max: regular width, but only ~440pt tall.
        XCTAssertEqual(GamesLayout(width: 832, horizontalSizeClass: .regular, verticalSizeClass: .compact), .list)
        XCTAssertEqual(GamesLayout(width: 1100, horizontalSizeClass: .regular, verticalSizeClass: .compact), .list)
        XCTAssertEqual(GamesLayout(width: 834, horizontalSizeClass: nil, verticalSizeClass: nil), .list)
    }

    func testIPadsKeepTheBoard() {
        XCTAssertEqual(GamesLayout(width: 744, horizontalSizeClass: .regular, verticalSizeClass: .regular), .board)  // iPad mini portrait
        XCTAssertEqual(GamesLayout(width: 834, horizontalSizeClass: .regular, verticalSizeClass: .regular), .board)  // iPad Air portrait
        XCTAssertEqual(GamesLayout(width: 1180, horizontalSizeClass: .regular, verticalSizeClass: .regular), .board) // iPad Air landscape
    }

    // MARK: - Detail layout

    func testDetailGoesSideBySideFrom760() {
        XCTAssertFalse(DetailLayout.isSideBySide(width: 759))
        XCTAssertTrue(DetailLayout.isSideBySide(width: 760))
        XCTAssertFalse(DetailLayout.isSideBySide(width: 669))  // Duo inner, portrait
        XCTAssertTrue(DetailLayout.isSideBySide(width: 951))   // Duo inner, landscape
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
