import XCTest
@testable import App
import SportsCalModel

/// ICS serialization rules (RFC 5545) and HTML/JSON-LD escaping for the public web
/// surface. Pure functions only — no Redis, no live data.
final class ICSSerializerTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_762_473_600) // 2025-11-07T00:00:00Z

    func testEscapesTextSpecials() {
        XCTAssertEqual(ICS.escapeText("a,b;c\\d"), "a\\,b\\;c\\\\d")
        XCTAssertEqual(ICS.escapeText("line1\nline2"), "line1\\nline2")
        XCTAssertEqual(ICS.escapeText("line1\r\nline2"), "line1\\nline2")
        XCTAssertEqual(ICS.escapeText("bell\u{07}"), "bell")
    }

    func testShortLinesAreNotFolded() {
        let line = String(repeating: "a", count: 75)
        XCTAssertEqual(ICS.fold(line), line)
    }

    func testFoldsAt75Octets() {
        let line = String(repeating: "a", count: 200)
        let folded = ICS.fold(line)
        let physical = folded.components(separatedBy: "\r\n")
        XCTAssertEqual(physical.count, 3)
        XCTAssertEqual(physical[0].utf8.count, 75)
        for continuation in physical.dropFirst() {
            XCTAssertTrue(continuation.hasPrefix(" "))
            XCTAssertLessThanOrEqual(continuation.utf8.count, 75)
        }
        // Unfolding restores the original.
        XCTAssertEqual(folded.replacingOccurrences(of: "\r\n ", with: ""), line)
    }

    func testFoldingNeverSplitsAMultibyteCharacter() {
        // "é" is 2 octets, "⚽" 3: a naive byte split would land mid-character.
        let line = "SUMMARY:" + String(repeating: "é⚽", count: 40)
        let folded = ICS.fold(line)
        for physical in folded.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(physical.utf8.count, 75)
            XCTAssertNotNil(String(data: Data(physical.utf8), encoding: .utf8))
        }
        XCTAssertEqual(folded.replacingOccurrences(of: "\r\n ", with: ""), line)
    }

    func testCalendarUsesCRLFAndRequiredProperties() {
        let start = Date(timeIntervalSince1970: 1_762_545_600) // 2025-11-07T20:00:00Z
        let calendar = ICSCalendar(
            name: "Arsenal, Spurs; and more",
            description: nil,
            url: "https://sportscal.app/team/133604/arsenal",
            events: [ICSEvent(uid: "123@sportscal.app",
                              timing: .timed(start: start, end: start.addingTimeInterval(7200)),
                              summary: "Arsenal vs Chelsea", description: "Premier League\nhttps://sportscal.app/g/123",
                              location: "Emirates Stadium, London", url: "https://sportscal.app/g/123")]
        )
        let out = calendar.render(stamp: stamp)
        XCTAssertTrue(out.hasPrefix("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"))
        XCTAssertTrue(out.hasSuffix("END:VCALENDAR\r\n"))
        // No bare LF anywhere.
        XCTAssertFalse(out.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        XCTAssertTrue(out.contains("X-WR-CALNAME:Arsenal\\, Spurs\\; and more\r\n"))
        XCTAssertTrue(out.contains("REFRESH-INTERVAL;VALUE=DURATION:PT6H\r\n"))
        XCTAssertTrue(out.contains("X-PUBLISHED-TTL:PT6H\r\n"))
        XCTAssertTrue(out.contains("UID:123@sportscal.app\r\n"))
        XCTAssertTrue(out.contains("DTSTAMP:20251107T000000Z\r\n"))
        XCTAssertTrue(out.contains("DTSTART:20251107T200000Z\r\n"))
        XCTAssertTrue(out.contains("DTEND:20251107T220000Z\r\n"))
        XCTAssertTrue(out.contains("LOCATION:Emirates Stadium\\, London\r\n"))
        XCTAssertTrue(out.contains("DESCRIPTION:Premier League\\nhttps://sportscal.app/g/123\r\n"))
        for line in out.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(line.utf8.count, 75)
        }
    }

    func testAllDayEventUsesDateValues() {
        let start = Date(timeIntervalSince1970: 1_762_473_600)
        let event = ICSEvent(uid: "g@x", timing: .allDay(start: start, endExclusive: start.addingTimeInterval(4 * 86_400)),
                             summary: "Golf", description: nil, location: nil, url: nil)
        let out = ICSCalendar(name: "x", events: [event]).render(stamp: stamp)
        XCTAssertTrue(out.contains("DTSTART;VALUE=DATE:20251107\r\n"))
        XCTAssertTrue(out.contains("DTEND;VALUE=DATE:20251111\r\n"))
    }

    func testFeedEventFromGame() {
        let site = PublicSite(baseURL: "https://example.test/")
        let game = Game(idEvent: "2475346", idLeague: "4391", idHomeTeam: "134931", idAwayTeam: "135907",
                        strHomeTeam: "Kansas City Chiefs", strAwayTeam: "Los Angeles Rams",
                        intHomeScore: "12", intAwayScore: "10", strStatus: "FT",
                        strTimestamp: "2026-08-15T20:00:00", isoDate: nil)
        let event = PublicPages.icsEvent(game, site: site, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(event.uid, "2475346@example.test")
        XCTAssertEqual(event.summary, "Los Angeles Rams @ Kansas City Chiefs")
        XCTAssertEqual(event.url, "https://example.test/g/2475346")
        XCTAssertTrue(event.description?.contains("Final: Los Angeles Rams 10 – 12 Kansas City Chiefs") == true)
    }
}

final class WebEscapeTests: XCTestCase {
    func testEscapesHTMLSpecials() {
        XCTAssertEqual(WebEscape.html("<script>alert('x')</script>"), "&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;")
        XCTAssertEqual(WebEscape.html("Tom & \"Jerry\""), "Tom &amp; &quot;Jerry&quot;")
        XCTAssertEqual(WebEscape.html("Atlético"), "Atlético")
    }

    func testScriptJSONCannotCloseTheScriptBlock() {
        let out = WebEscape.scriptJSON(#"{"name":"</script><script>x()</script>&"}"#)
        XCTAssertFalse(out.contains("<"))
        XCTAssertFalse(out.contains(">"))
        XCTAssertFalse(out.contains("&"))
        let decoded = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: String]
        XCTAssertEqual(decoded?["name"], "</script><script>x()</script>&")
    }

    func testSlug() {
        XCTAssertEqual(WebEscape.slug("Paris Saint-Germain"), "paris-saint-germain")
        XCTAssertEqual(WebEscape.slug("Atlético Madrid"), "atletico-madrid")
        XCTAssertEqual(WebEscape.slug("  Brighton & Hove Albion!! "), "brighton-hove-albion")
    }

    func testSafeIDs() {
        XCTAssertTrue(WebEscape.isSafeID("134867"))
        XCTAssertTrue(WebEscape.isSafeID("ncaaf-145"))
        XCTAssertFalse(WebEscape.isSafeID(""))
        XCTAssertFalse(WebEscape.isSafeID("1<2"))
        XCTAssertFalse(WebEscape.isSafeID("../etc"))
        XCTAssertFalse(WebEscape.isSafeID(String(repeating: "1", count: 41)))
    }

    func testPagesEscapeUpstreamNames() {
        let evil = "<img src=x onerror=alert(1)>"
        let game = Game(idEvent: "1", idLeague: "4328", idHomeTeam: "10", idAwayTeam: "11",
                        strHomeTeam: evil, strAwayTeam: "Away \"FC\"",
                        strTimestamp: "2030-01-01T15:00:00", isoDate: nil)
        let schedule = PublicScheduleIndex.index([game], generation: 1)
        let site = PublicSite(baseURL: "https://sportscal.app")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let teamHTML = PublicPages.teamPage(schedule.teams["10"]!, schedule: schedule, site: site, now: now)
        let gameHTML = PublicPages.gamePage(game, schedule: schedule, site: site, now: now)
        let leagueHTML = PublicPages.leaguePage(schedule.leagues["4328"]!, schedule: schedule, site: site, now: now)
        for html in [teamHTML, gameHTML, leagueHTML] {
            XCTAssertFalse(html.contains("<img"), "unescaped upstream markup")
            XCTAssertTrue(html.contains("&lt;img src=x onerror=alert(1)&gt;"))
            XCTAssertTrue(html.contains("app-id=1580232928"))
            XCTAssertTrue(html.contains("<link rel=\"canonical\""))
        }
        XCTAssertTrue(gameHTML.contains("\"@type\":\"SportsEvent\""))
        XCTAssertTrue(teamHTML.contains("webcal://sportscal.app/cal/team/10.ics"))
    }

    func testIndexGroupsTeamsAndLeagues() {
        let a = Game(idEvent: "1", idLeague: "4328", idHomeTeam: "10", idAwayTeam: "11",
                     strHomeTeam: "Arsenal", strAwayTeam: "Chelsea", strTimestamp: "2030-01-01T15:00:00", isoDate: nil)
        let b = Game(idEvent: "2", idLeague: "4482", idHomeTeam: "12", idAwayTeam: "10",
                     strHomeTeam: "Spurs", strAwayTeam: "Arsenal", strTimestamp: "2030-01-08T15:00:00", isoDate: nil)
        let c = Game(idEvent: "3", idLeague: "4328", idHomeTeam: "10", idAwayTeam: "12",
                     strHomeTeam: "Arsenal", strAwayTeam: "Spurs", strTimestamp: "2030-01-15T15:00:00", isoDate: nil)
        let golf = Game(idEvent: "4", idLeague: "4425", strHomeTeam: "The Masters", strAwayTeam: "TBD",
                        strTimestamp: "2030-04-10T12:00:00", isoDate: nil)
        let schedule = PublicScheduleIndex.index([c, golf, a, b, a], generation: 1)
        XCTAssertEqual(schedule.teams["10"]?.games.compactMap(\.idEvent), ["1", "2", "3"])
        XCTAssertEqual(schedule.teams["10"]?.primaryLeagueID, "4328")
        XCTAssertEqual(schedule.teams["10"]?.slug, "arsenal")
        XCTAssertEqual(schedule.leagues["4328"]?.games.count, 2)
        XCTAssertEqual(schedule.leagues["4425"]?.games.count, 1)
        XCTAssertEqual(schedule.teams.count, 3) // no team page for a golf tournament
        let sitemap = PublicPages.sitemap(schedule, site: PublicSite(baseURL: "https://sportscal.app"))
        XCTAssertTrue(sitemap.contains("<loc>https://sportscal.app/team/10/arsenal</loc>"))
        XCTAssertTrue(sitemap.contains("<loc>https://sportscal.app/league/4328/english-premier-league</loc>"))
    }

    func testSeasonLabel() {
        XCTAssertEqual(PublicGame.seasonLabel("2025-2026"), "2025-26")
        XCTAssertEqual(PublicGame.seasonLabel("2026"), "2026")
    }
}
