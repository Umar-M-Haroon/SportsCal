import XCTest
@testable import App
import SportsCalModel

/// Pins the loose-name stage of the ESPN→TheSportsDB merge.
///
/// Every pair below was taken from the production `/schedules` payload on 2026-09-16,
/// where each showed up twice: the two sources spell the club differently, no match key
/// hit, and the unmatched ESPN row was appended next to the TheSportsDB one.
final class LooseNameDedupTests: XCTestCase {

    private let job = ESPNFetchJob()
    private let resolver = TeamAliasResolver(teams: [])

    private func date(_ iso: String) -> Date {
        guard let date = ISO8601DateFormatter().date(from: iso) else { fatalError("bad date \(iso)") }
        return date
    }

    private func game(_ id: String, _ home: String, _ away: String,
                      league: String = "4335", at iso: String = "2026-09-16T19:30:00Z") -> Game {
        TestGameFactory.make(idEvent: id, idLeague: league, strHomeTeam: home, strAwayTeam: away,
                             isoDate: date(iso))
    }

    private func mergedCount(_ schedule: Game, _ espn: Game) -> Int {
        job.mergeSportEvents(schedule: LiveEvent(events: [schedule]),
                             espn: LiveEvent(events: [espn]),
                             resolver: resolver)?.events.count ?? 0
    }

    /// The six real duplicates. Each must collapse to one row.
    func testProductionDuplicatesCollapse() {
        let pairs = [
            ("Racing de Santander", "Racing Santander"),
            ("Celje", "NK Celje"),
            ("Hapoel Be'er Sheva", "Hapoel Be'er"),
            ("Deportivo de A Coruña", "Deportivo"),
            ("Jagiellonia Białystok", "Jagiellonia Bialystok"),
            ("Athletic Bilbao", "Athletic Club"),
        ]
        for (tsdb, espn) in pairs {
            let count = mergedCount(game("TSDB", tsdb, "Sevilla"), game("401", espn, "Sevilla"))
            XCTAssertEqual(count, 1, "\"\(tsdb)\" and \"\(espn)\" should be one fixture, not \(count)")
        }
    }

    /// The merged row keeps the schedule's identity and takes ESPN's live fields.
    func testCollapsedRowKeepsScheduleIdentity() {
        let schedule = game("TSDB1", "Deportivo de A Coruña", "Sevilla")
        var espn = game("401882873", "Deportivo", "Sevilla")
        espn = espn.updated(intHomeScore: "2", intAwayScore: "1", strStatus: "post")
        let merged = job.mergeSportEvents(schedule: LiveEvent(events: [schedule]),
                                          espn: LiveEvent(events: [espn]),
                                          resolver: resolver)?.events ?? []
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].idEvent, "TSDB1")
        XCTAssertEqual(merged[0].strHomeTeam, "Deportivo")
        XCTAssertEqual(merged[0].intHomeScore, "2")
    }

    /// The exact prod state on 2026-09-16: TheSportsDB's row froze mid-match at "2H 4-2"
    /// while ESPN had the 7-2 final, and because the names never matched, both rows shipped.
    /// One row must survive carrying ESPN's final — otherwise collapsing the duplicate would
    /// leave the *stale* row behind.
    func testStaleScheduleRowTakesESPNFinal() {
        let schedule = TestGameFactory.make(
            idEvent: "2506219", idLeague: "4335",
            strHomeTeam: "Barcelona", strAwayTeam: "Racing de Santander",
            intHomeScore: "4", intAwayScore: "2", strStatus: "2H",
            isoDate: date("2026-09-16T19:30:00Z")
        )
        let espn = TestGameFactory.make(
            idEvent: "401882871", idLeague: "4335",
            strHomeTeam: "Barcelona", strAwayTeam: "Racing Santander",
            intHomeScore: "7", intAwayScore: "2", strStatus: "post",
            isoDate: date("2026-09-16T19:30:00Z")
        )
        let merged = job.mergeSportEvents(schedule: LiveEvent(events: [schedule]),
                                          espn: LiveEvent(events: [espn]),
                                          resolver: resolver)?.events ?? []
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].idEvent, "2506219")
        XCTAssertEqual(merged[0].intHomeScore, "7")
        XCTAssertEqual(merged[0].intAwayScore, "2")
        XCTAssertEqual(merged[0].strStatus, "post")
    }

    // MARK: - What must NOT collapse

    /// Different fixtures between similarly named clubs stay separate.
    func testDifferentOpponentsDoNotCollapse() {
        XCTAssertEqual(mergedCount(game("TSDB", "Celje", "Sevilla"),
                                   game("401", "NK Celje", "Barcelona")), 2)
    }

    /// A short name must not swallow a longer unrelated one.
    func testShortPrefixDoesNotSwallow() {
        XCTAssertEqual(mergedCount(game("TSDB", "Real", "Sevilla"),
                                   game("401", "Real Sociedad", "Sevilla")), 2)
    }

    func testDifferentLeaguesDoNotCollapse() {
        XCTAssertEqual(mergedCount(game("TSDB", "Celje", "Sevilla", league: "4335"),
                                   game("401", "NK Celje", "Sevilla", league: "4481")), 2)
    }

    /// Two legs of a tie on the same day are different fixtures.
    func testDistantKickoffsDoNotCollapse() {
        XCTAssertEqual(mergedCount(game("TSDB", "Celje", "Sevilla", at: "2026-09-16T12:00:00Z"),
                                   game("401", "NK Celje", "Sevilla", at: "2026-09-16T19:30:00Z")), 2)
    }

    // MARK: - Key shape

    func testLooseKeyFoldsAccentsAndClubWords() {
        XCTAssertEqual(job.looseTeamKey("Jagiellonia Białystok"), job.looseTeamKey("Jagiellonia Bialystok"))
        XCTAssertEqual(job.looseTeamKey("NK Celje"), job.looseTeamKey("Celje"))
        XCTAssertEqual(job.looseTeamKey("Racing de Santander"), job.looseTeamKey("Racing Santander"))
        XCTAssertEqual(job.looseTeamKey("Beşiktaş"), "besiktas")
    }

    func testLooselySameTeamNeedsAPrefixOfRealLength() {
        XCTAssertTrue(job.looselySameTeam("hapoelbeer", "hapoelbeersheva"))
        XCTAssertFalse(job.looselySameTeam("real", "realsociedad"))
        XCTAssertFalse(job.looselySameTeam("", "celje"))
        XCTAssertFalse(job.looselySameTeam("bayern", "borussia"))
    }
}
