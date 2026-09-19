import XCTest
@testable import SportsCalModel

/// The golf tours beyond the PGA TOUR: ESPN-only leagues, each with its own majors.
final class GolfTourTests: XCTestCase {

    private func event(_ name: String, tour: Leagues, endDate: String? = nil) -> Game {
        Game(idEvent: "1", idLeague: "\(tour.rawValue)", strHomeTeam: name, strAwayTeam: "Leader",
             strTimestamp: "2026-09-17T04:00Z", isoDate: nil, endDate: endDate)
    }

    /// `isSoccer` is defined by exclusion, so a new league that isn't added to its list
    /// silently becomes a soccer league — and gets fetched, filtered and bucketed as one.
    func testEveryGolfTourIsGolfAndNotSoccer() {
        for tour in [Leagues.pga, .dpWorld, .livGolf, .lpga, .championsTour, .kornFerry] {
            XCTAssertTrue(tour.isGolf, "\(tour) should be golf")
            XCTAssertFalse(tour.isSoccer, "\(tour) must not fall through to soccer")
            XCTAssertEqual(tour.sport, "golf")
            XCTAssertEqual(SportType(league: tour), .golf)
            XCTAssertNotNil(tour.espnSlug)
            XCTAssertEqual(tour.espnSlug.flatMap { Leagues(slug: $0) }, tour, "slug must round-trip")
        }
    }

    func testMultiDayEventKnowsItsEnd() {
        let tournament = event("Biltmore Championship Asheville", tour: .pga, endDate: "2026-09-20T04:00Z")
        XCTAssertNotNil(tournament.endDateParsed)
        XCTAssertNil(event("Biltmore Championship Asheville", tour: .pga).endDateParsed)
    }
}
