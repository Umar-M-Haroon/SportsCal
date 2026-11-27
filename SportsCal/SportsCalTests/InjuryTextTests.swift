import XCTest
import SportsCalModel
@testable import Scoreline

/// How an injury reads ("Right hip inflammation", "Back Sun, Nov 29 · in 3 days") and
/// how names are found ("doncic" → Dončić).
final class InjuryTextTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    /// Thursday, Nov 26 2026, mid-afternoon in New York.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 15))! }

    private func injury(_ name: String = "Jock Landale", status: String = "Out", bodyPart: String? = "Hip",
                        injury: String? = "Inflammation", side: String? = "Right", returnDate: String? = "2026-11-29",
                        summary: String? = nil, details: String? = nil) -> PlayerInjury {
        PlayerInjury(id: name, playerName: name, league: "nba", teamName: "Atlanta Hawks", status: status,
                     bodyPart: bodyPart, injury: injury, side: side, returnDate: returnDate,
                     summary: summary, details: details)
    }

    func testHeadlineReadsSideBodyPartAndInjury() {
        XCTAssertEqual(InjuryText.headline(injury()), "Right hip inflammation")
        XCTAssertEqual(InjuryText.headline(injury(injury: nil, side: nil)), "Hip")
        XCTAssertEqual(InjuryText.headline(injury(bodyPart: nil, injury: nil, side: nil)), "Out")
        XCTAssertEqual(InjuryText.headline(injury(status: "Suspension")), "Suspended")
    }

    func testReturnLineCountsDaysWeeksAndMonths() {
        XCTAssertEqual(InjuryText.returnLine(injury(returnDate: "2026-11-29"), now: now, calendar: calendar),
                       "Back Sun, Nov 29 · in 3 days")
        XCTAssertEqual(InjuryText.returnLine(injury(returnDate: "2026-11-27"), now: now, calendar: calendar),
                       "Back tomorrow · Fri, Nov 27")
        XCTAssertEqual(InjuryText.returnLine(injury(returnDate: "2026-12-19"), now: now, calendar: calendar),
                       "Back Sat, Dec 19 · in about 3 weeks")
        XCTAssertEqual(InjuryText.returnLine(injury(returnDate: "2027-03-17"), now: now, calendar: calendar),
                       "Back Wed, Mar 17 · in about 4 months")
        XCTAssertEqual(InjuryText.returnLine(injury(returnDate: "2026-11-20"), now: now, calendar: calendar),
                       "Could return any day")
        XCTAssertEqual(InjuryText.returnLine(injury(returnDate: nil), now: now, calendar: calendar),
                       "No return date yet")
        XCTAssertEqual(InjuryText.returnLine(injury(details: "He suffered a season-ending ACL tear."), now: now, calendar: calendar),
                       "Out for the season")
    }

    func testSpokenAnswerSaysWhatAndWhen() {
        XCTAssertEqual(InjuryText.answer(injury(), now: now, calendar: calendar),
                       "Jock Landale (Atlanta Hawks) is out with right hip inflammation. Estimated return: Sunday, November 29, in 3 days.")
        XCTAssertEqual(InjuryText.answer(injury(status: "Injured Reserve", returnDate: nil), now: now, calendar: calendar),
                       "Jock Landale (Atlanta Hawks) is on injured reserve with right hip inflammation. There's no estimated return date yet.")
    }

    func testSearchMatchesFullNamesSurnamesPrefixesAndAccents() {
        let list = [injury("Luka Dončić"), injury("Jock Landale"), injury("CJ McCollum"), injury("Landon Dickerson")]
        XCTAssertEqual(InjurySearch.rank(list, query: "doncic").map(\.playerName), ["Luka Dončić"])
        XCTAssertEqual(InjurySearch.rank(list, query: "Jock Landale").first?.playerName, "Jock Landale")
        XCTAssertEqual(InjurySearch.rank(list, query: "landale").first?.playerName, "Jock Landale")
        XCTAssertEqual(InjurySearch.rank(list, query: "lan").map(\.playerName), ["Jock Landale", "Landon Dickerson"])
        XCTAssertEqual(InjurySearch.rank(list, query: "c.j. mccollum").first?.playerName, "CJ McCollum")
        XCTAssertTrue(InjurySearch.rank(list, query: "l").isEmpty, "one letter is too vague")
    }

    func testLongestOutSortsFirst() {
        let short = injury("A", returnDate: "2026-11-28"), long = injury("B", returnDate: "2027-01-10")
        XCTAssertEqual([short, long].sorted(by: InjuryText.severityOrder).map(\.playerName), ["B", "A"])
    }
}
