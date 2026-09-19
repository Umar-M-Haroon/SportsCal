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

    func testTiersAreReadPerTour() {
        XCTAssertEqual(event("The Chevron Championship", tour: .lpga).eventTier, .major)
        XCTAssertEqual(event("AIG Women's Open", tour: .lpga).eventTier, .major)
        XCTAssertEqual(event("U.S. Women's Open pres. by Ally", tour: .lpga).eventTier, .major)
        // The Canadian stop shares "Women's Open" with two majors but isn't one.
        XCTAssertEqual(event("CPKC Women's Open", tour: .lpga).eventTier, .tour)
        XCTAssertEqual(event("Walmart NW Arkansas Championship pres. by P&G", tour: .lpga).eventTier, .tour)
        XCTAssertEqual(event("Senior PGA Championship", tour: .championsTour).eventTier, .major)
        XCTAssertEqual(event("PURE Insurance Championship", tour: .championsTour).eventTier, .tour)
        XCTAssertEqual(event("BMW PGA Championship", tour: .dpWorld).eventTier, .premier)
        XCTAssertEqual(event("LIV Golf Michigan - Stroke Play", tour: .livGolf).eventTier, .tour)
        XCTAssertEqual(event("Nationwide Children's Hospital Championship", tour: .kornFerry).eventTier, .tour)
    }

    /// The PGA table must not leak across tours: "BMW PGA Championship" contains
    /// "pga championship", which is a men's major only on the PGA board.
    func testDPWorldBMWIsNotAMajor() {
        XCTAssertNotEqual(event("BMW PGA Championship", tour: .dpWorld).eventTier, .major)
        XCTAssertEqual(event("PGA Championship", tour: .pga).eventTier, .major)
    }

    func testMultiDayEventKnowsItsEnd() {
        let tournament = event("Biltmore Championship Asheville", tour: .pga, endDate: "2026-09-20T04:00Z")
        XCTAssertNotNil(tournament.endDateParsed)
        XCTAssertNil(event("Biltmore Championship Asheville", tour: .pga).endDateParsed)
    }
}
