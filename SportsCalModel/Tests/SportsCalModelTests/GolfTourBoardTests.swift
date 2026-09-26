import XCTest
@testable import SportsCalModel

/// Browse's golf tour picker (`GolfTourBoard`) and course par (`GolfPar`, `Game.coursePar`).
final class GolfTourBoardTests: XCTestCase {

    private func event(_ id: String, _ name: String, tour: Leagues, start: String, end: String? = nil,
                       status: String? = nil, courseInfo: GolfCourseInfo? = nil) -> Game {
        Game(idEvent: id, idLeague: "\(tour.rawValue)", strHomeTeam: name, strAwayTeam: "Leader",
             strStatus: status, strTimestamp: start, isoDate: nil, golfCourseInfo: courseInfo, endDate: end)
    }

    private func day(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    // MARK: Tours

    func testToursAreOnlyThoseWithEventsInPickerOrder() {
        let games = [
            event("1", "Korn Ferry Tour Championship", tour: .kornFerry, start: "2026-09-10T04:00Z"),
            event("2", "BMW PGA Championship", tour: .dpWorld, start: "2026-09-17T04:00Z"),
            event("3", "Tour Championship", tour: .pga, start: "2026-08-20T04:00Z"),
            Game(idEvent: "4", idLeague: "\(Leagues.atp.rawValue)", strHomeTeam: "A", strAwayTeam: "B", isoDate: nil),
        ]
        XCTAssertEqual(GolfTourBoard.tours(in: games), [.pga, .dpWorld, .kornFerry])
        XCTAssertEqual(Set(Leagues.golfTours), Set(Leagues.allCases.filter(\.isGolf)), "every golf league is pickable")
        XCTAssertTrue(Leagues.golfTours.allSatisfy { $0.golfTourShortName != nil })
    }

    func testDefaultTourSkipsHiddenToursButNeverLeavesNothing() {
        let tours: [Leagues] = [.pga, .dpWorld, .lpga]
        XCTAssertEqual(GolfTourBoard.defaultTour(in: tours, hidden: []), .pga)
        XCTAssertEqual(GolfTourBoard.defaultTour(in: tours, hidden: [Leagues.pga.leagueName]), .dpWorld)
        XCTAssertEqual(GolfTourBoard.defaultTour(in: [.pga], hidden: [Leagues.pga.leagueName]), .pga)
        XCTAssertNil(GolfTourBoard.defaultTour(in: [], hidden: []))
    }

    func testEventsAreFilteredToTheTourAndDeduplicated() {
        let games = [
            event("1", "Procore Championship", tour: .pga, start: "2026-09-10T04:00Z"),
            event("2", "BMW PGA Championship", tour: .dpWorld, start: "2026-09-17T04:00Z"),
            event("1", "Procore Championship", tour: .pga, start: "2026-09-10T04:00Z", status: "in"),
        ]
        let pga = GolfTourBoard.events(for: .pga, in: games)
        XCTAssertEqual(pga.map(\.idEvent), ["1"])
        XCTAssertEqual(GolfTourBoard.events(for: .dpWorld, in: games).map(\.idEvent), ["2"])
    }

    /// A Thursday–Sunday event stays upcoming through Sunday, then moves to results.
    func testMultiDayEventIsUpcomingUntilItsLastDay() {
        let tournament = event("1", "Open de France", tour: .dpWorld,
                               start: "2026-09-24T04:00Z", end: "2026-09-27T04:00Z")
        let utc = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        let sunday = cal.startOfDay(for: day("2026-09-27T12:00:00Z"))
        let monday = cal.startOfDay(for: day("2026-09-28T12:00:00Z"))
        XCTAssertEqual(GolfTourBoard.upcoming([tournament], startOfToday: sunday).count, 1)
        XCTAssertTrue(GolfTourBoard.past([tournament], startOfToday: sunday).isEmpty)
        XCTAssertTrue(GolfTourBoard.upcoming([tournament], startOfToday: monday).isEmpty)
        XCTAssertEqual(GolfTourBoard.past([tournament], startOfToday: monday).count, 1)
    }

    func testUpcomingPutsLiveFirstAndPastIsNewestFirst() {
        let today = day("2026-09-20T00:00:00Z")
        let later = event("later", "Later", tour: .pga, start: "2026-10-01T04:00Z", end: "2026-10-04T04:00Z")
        let soon = event("soon", "Soon", tour: .pga, start: "2026-09-24T04:00Z", end: "2026-09-27T04:00Z")
        // Live but with a stale span (no end date, started days ago): still upcoming.
        let live = event("live", "Live", tour: .pga, start: "2026-09-17T04:00Z", status: "in")
        XCTAssertEqual(GolfTourBoard.upcoming([later, soon, live], startOfToday: today).map(\.idEvent),
                       ["live", "soon", "later"])

        let old = event("old", "Old", tour: .pga, start: "2026-08-01T04:00Z", end: "2026-08-04T04:00Z")
        let recent = event("recent", "Recent", tour: .pga, start: "2026-09-10T04:00Z", end: "2026-09-13T04:00Z")
        XCTAssertEqual(GolfTourBoard.past([old, recent, live], startOfToday: today).map(\.idEvent),
                       ["recent", "old"])
    }

    // MARK: Par

    func testParIsInferredFromRoundsAndIgnoresOutliers() {
        let rounds: [(strokes: Double?, toPar: String?)] = [
            (65, "-6"), (64, "-7"), (71, "E"), (74, "+3"),
            (33, "-2"),        // a round in progress: par of the holes played
            (nil, nil), (70, "--"),
        ]
        XCTAssertEqual(GolfPar.inferred(fromRounds: rounds), 71)
    }

    func testParNeedsAgreement() {
        XCTAssertNil(GolfPar.inferred(fromRounds: []))
        XCTAssertNil(GolfPar.inferred(fromRounds: [(65, "-6")]), "one round is not enough")
        XCTAssertNil(GolfPar.inferred(fromRounds: [(65, "-6"), (65, "-7"), (70, "-2"), (70, "-1")]), "tie")
        // A feed that put strokes in displayValue would give 0 — never a par.
        XCTAssertNil(GolfPar.inferred(fromRounds: [(65, "65"), (70, "70")]))
    }

    /// Real DP World board (FedEx Open de France, after round 3): par comes from the rounds,
    /// not from a hardcoded table, and the in-progress round 4 is ignored.
    func testScoreboardDecodeInfersParForANonPGATour() throws {
        let scoreboard = try XCTUnwrap(
            JSONLoader.load(file: "DPWorldGolfScoreboard", type: Scoreboard.self) as? Scoreboard
        )
        let live = try XCTUnwrap(LiveEvent(events: scoreboard, league: .dpWorld))
        let game = try XCTUnwrap(live.events.first)
        XCTAssertEqual(game.golfTour, .dpWorld)
        XCTAssertEqual(game.golfCourseInfo?.par, 71)
        XCTAssertEqual(game.coursePar, 71)
    }

    func testCourseParFallbackIsOnlyTheMasters() {
        XCTAssertEqual(event("1", "Masters Tournament", tour: .pga, start: "2026-04-09T04:00Z").coursePar, 72)
        // Majors that rotate venues change par with them: no guess.
        XCTAssertNil(event("2", "PGA Championship", tour: .pga, start: "2026-05-14T04:00Z").coursePar)
        XCTAssertNil(event("3", "U.S. Open", tour: .pga, start: "2026-06-18T04:00Z").coursePar)
        XCTAssertNil(event("4", "The Open", tour: .pga, start: "2026-07-16T04:00Z").coursePar)
        // Other tours' "Masters" aren't Augusta.
        XCTAssertNil(event("5", "Omega European Masters", tour: .dpWorld, start: "2026-08-27T04:00Z").coursePar)
        // Feed data always wins.
        let info = GolfCourseInfo(courseName: "Augusta National", par: 72)
        XCTAssertEqual(event("6", "BMW PGA Championship", tour: .dpWorld, start: "2026-09-17T04:00Z",
                             courseInfo: GolfCourseInfo(courseName: "Wentworth", par: 72)).coursePar, 72)
        XCTAssertEqual(event("7", "Anything", tour: .lpga, start: "2026-09-17T04:00Z", courseInfo: info).coursePar, 72)
    }
}
