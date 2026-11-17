import XCTest
@testable import App
import SportsCalModel

/// Pins the live tennis bucket built from the per-tour ESPN boards
/// (`ESPNFetchJob.tennisLiveEvent(from:)`).
///
/// ESPN serves a combined event's whole draw — men's, women's and mixed — on both the
/// `atp` and the `wta` board under the same match IDs. Concatenating the two boards
/// shipped every match twice (~46% of a live frame) and, because the v2 delta protocol
/// keys signatures by idEvent, made every tick re-send the whole draw.
final class TennisLiveDedupTests: XCTestCase {

    private let atp = "\(Leagues.atp.rawValue)"
    private let wta = "\(Leagues.wta.rawValue)"

    /// A combined slam on both boards, a WTA-only event on the WTA board, and an ATP
    /// event whose draw isn't out yet (a placeholder) on the ATP board.
    private func boards() throws -> [Leagues: Scoreboard] {
        let slam = event(id: "189-2026", name: "US Open", draws: [
            ("mens-singles",   ["101", "102"]),
            ("womens-singles", ["201", "202"]),
            ("mens-doubles",   ["111"]),
            ("womens-doubles", ["211"]),
            ("mixed-doubles",  ["301"]),
        ])
        let wtaOnly = event(id: "998-2026", name: "Montreux Nestle Open", draws: [("womens-singles", ["501"])])
        let atpPlaceholder = event(id: "777-2026", name: "Chengdu Open", draws: [])
        return [
            .atp: try scoreboard(slug: "atp", events: [slam, atpPlaceholder]),
            .wta: try scoreboard(slug: "wta", events: [slam, wtaOnly]),
        ]
    }

    // MARK: - One row per match

    func testCombinedDrawShipsOncePerMatch() throws {
        let games = ESPNFetchJob.tennisLiveEvent(from: try boards()).events
        let ids = games.compactMap(\.idEvent)
        XCTAssertEqual(ids.count, games.count, "every live tennis row needs an idEvent")
        XCTAssertEqual(Set(ids).count, ids.count, "a match shipped more than once")
        XCTAssertEqual(Set(ids), ["101", "102", "201", "202", "111", "211", "301", "501"])
    }

    /// The pre-fix behaviour, for contrast: the raw concatenation of both boards carries
    /// every combined-draw match twice. If this stops holding, the fixture no longer
    /// reproduces the bug and the test above proves nothing.
    func testRawConcatenationOfBothBoardsDuplicatesTheCombinedDraw() throws {
        let raw = try boards().flatMap { league, board in LiveEvent(events: board, league: league)?.events ?? [] }
            .filter { !$0.isTennisDrawPlaceholder }
        XCTAssertEqual(raw.count, 15) // 7 slam matches × 2 boards + 1 WTA-only
        XCTAssertEqual(Set(raw.compactMap(\.idEvent)).count, 8)
    }

    func testDedupHalvesTheEncodedCombinedDraw() throws {
        let boards = try boards()
        let raw = boards.flatMap { league, board in LiveEvent(events: board, league: league)?.events ?? [] }
            .filter { !$0.isTennisDrawPlaceholder }
        let deduped = ESPNFetchJob.tennisLiveEvent(from: boards)
        let rawBytes = try JSONEncoder().encode(LiveEvent(events: raw)).count
        let dedupedBytes = try JSONEncoder().encode(deduped).count
        XCTAssertLessThan(Double(dedupedBytes), Double(rawBytes) * 0.65,
                          "deduped \(dedupedBytes) B vs raw \(rawBytes) B")
    }

    // MARK: - Tour assignment

    /// Each match takes its tour from its draw, whichever board it was read from.
    func testEachMatchCarriesItsDrawsTour() throws {
        let byID = Dictionary(uniqueKeysWithValues: ESPNFetchJob.tennisLiveEvent(from: try boards()).events.compactMap { g in
            g.idEvent.map { ($0, g) }
        })
        for id in ["101", "102", "111"] { XCTAssertEqual(byID[id]?.idLeague, atp, id) }
        for id in ["201", "202", "211", "501"] { XCTAssertEqual(byID[id]?.idLeague, wta, id) }

        // Mixed doubles: one row, filed under ATP for a stable identity, admitted under
        // both tours by `tennisTours`.
        let mixed = try XCTUnwrap(byID["301"])
        XCTAssertEqual(mixed.idLeague, atp)
        XCTAssertEqual(mixed.drawSlug, "mixed-doubles")
        XCTAssertEqual(mixed.tennisTours, [.atp, .wta])
    }

    /// Clients that predate `drawSlug` filter tennis by `idLeague` alone (4464 / 4517).
    /// A user who only follows the WTA must still get every women's match — and no
    /// longer gets the men's draw mis-filed under the WTA.
    func testLeagueOnlyFilteringStillFindsEveryWTAMatch() throws {
        let games = ESPNFetchJob.tennisLiveEvent(from: try boards()).events
        let wtaOnly = Set(games.filter { $0.idLeague == wta }.compactMap(\.idEvent))
        let atpOnly = Set(games.filter { $0.idLeague == atp }.compactMap(\.idEvent))
        XCTAssertEqual(wtaOnly, ["201", "202", "211", "501"])
        XCTAssertEqual(atpOnly, ["101", "102", "111", "301"])

        // Current clients go by the draw: mixed doubles shows under both.
        let wtaByDraw = Set(games.filter { $0.belongsToTennisTour(.wta) }.compactMap(\.idEvent))
        XCTAssertEqual(wtaByDraw, ["201", "202", "211", "501", "301"])
    }

    // MARK: - Stability

    /// The surviving copy must not depend on dictionary order, or the delta protocol sees
    /// phantom changes on every tick.
    func testOutputIsIndependentOfBoardOrder() throws {
        let original = try boards()
        let reversed = Dictionary(uniqueKeysWithValues: original.reversed().map { ($0.key, $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(
            try encoder.encode(ESPNFetchJob.tennisLiveEvent(from: original)),
            try encoder.encode(ESPNFetchJob.tennisLiveEvent(from: reversed))
        )
    }

    /// Either board on its own yields the combined draw's rows identically, so dropping the
    /// second copy loses nothing.
    func testEitherBoardAloneYieldsTheSameCombinedDraw() throws {
        let boards = try boards()
        let fromATP = ESPNFetchJob.tennisLiveEvent(from: [.atp: try XCTUnwrap(boards[.atp])]).events
        let fromWTA = ESPNFetchJob.tennisLiveEvent(from: [.wta: try XCTUnwrap(boards[.wta])]).events
            .filter { $0.tournamentName == "US Open" }
        XCTAssertEqual(fromATP, fromWTA)
    }

    func testDrawPlaceholderNeverReachesTheLiveFeed() throws {
        let games = ESPNFetchJob.tennisLiveEvent(from: try boards()).events
        XCTAssertFalse(games.contains { $0.isTennisDrawPlaceholder })
        XCTAssertFalse(games.contains { $0.idEvent == "777-2026" })
    }

    // MARK: - Fixture

    /// Mirrors ESPN's tennis shape: tournament event → groupings → competitions.
    private func event(id: String, name: String, draws: [(String, [String])]) -> String {
        func competitor(_ id: String, _ homeAway: String) -> String {
            #"{"id":"\#(id)","uid":"a\#(id)","type":"athlete","homeAway":"\#(homeAway)","athlete":{"id":"\#(id)","displayName":"Player \#(id)"}}"#
        }
        let groupings = draws.map { slug, ids in
            let comps = ids.map { matchID in
                #"{"id":"\#(matchID)","uid":"c\#(matchID)","date":"2026-09-06T15:00Z","competitors":[\#(competitor(matchID + "1", "home")),\#(competitor(matchID + "2", "away"))]}"#
            }.joined(separator: ",")
            return #"{"grouping":{"slug":"\#(slug)"},"competitions":[\#(comps)]}"#
        }.joined(separator: ",")
        return #"{"id":"\#(id)","uid":"u\#(id)","date":"2026-08-24T04:00Z","name":"\#(name)","groupings":[\#(groupings)]}"#
    }

    private func scoreboard(slug: String, events: [String]) throws -> Scoreboard {
        let json = #"{"leagues":[{"id":"850","slug":"\#(slug)"}],"events":[\#(events.joined(separator: ","))]}"#
        return try JSONDecoder().decode(Scoreboard.self, from: Data(json.utf8))
    }
}
