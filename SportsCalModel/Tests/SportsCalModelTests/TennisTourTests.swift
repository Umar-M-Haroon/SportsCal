import XCTest
@testable import SportsCalModel

/// Pins how a tennis match's tour is decided.
///
/// ESPN serves a combined slam's *entire* draw on both the `atp` and the `wta`
/// scoreboard — the same match IDs, women's matches included. Measured on the 2026 US
/// Open: 625 matches, identical on both boards, zero unique to either. Taking the tour
/// from the board therefore filed every women's match under ATP (emptying the Women's
/// tab) and, because the two boards were concatenated, emitted every match twice.
final class TennisTourTests: XCTestCase {

    // MARK: - Draw → tour

    func testMensDrawsAreATP() {
        for slug in ["mens-singles", "mens-doubles"] {
            guard case .tour(.atp)? = TennisDraw(slug: slug) else {
                return XCTFail("\(slug) should be ATP")
            }
        }
    }

    func testWomensDrawsAreWTA() {
        for slug in ["womens-singles", "womens-doubles"] {
            guard case .tour(.wta)? = TennisDraw(slug: slug) else {
                return XCTFail("\(slug) should be WTA")
            }
        }
    }

    func testMixedDoublesIsBothTours() {
        guard case .mixed? = TennisDraw(slug: "mixed-doubles") else {
            return XCTFail("mixed-doubles should be .mixed")
        }
        // It still needs one stable `idLeague`; both-tour membership is expressed by
        // `isMixedDoubles`, not by emitting a second row under the other tour.
        XCTAssertEqual(TennisDraw.mixed.idLeague, .atp)
    }

    /// An unknown slug must not be guessed at — callers fall back to the board's league.
    func testUnknownSlugIsNil() {
        XCTAssertNil(TennisDraw(slug: "juniors-singles"))
        XCTAssertNil(TennisDraw(slug: nil))
        XCTAssertNil(TennisDraw(slug: ""))
    }

    // MARK: - Tour membership

    private func match(league: Leagues, draw: String?) -> Game {
        Game(idEvent: "1", idLeague: "\(league.rawValue)", strHomeTeam: "A", strAwayTeam: "B",
             isoDate: nil, drawSlug: draw)
    }

    func testSingleTourMatchAppearsOnlyUnderItsOwnTour() {
        let mens = match(league: .atp, draw: "mens-singles")
        XCTAssertTrue(mens.belongsToTennisTour(.atp))
        XCTAssertFalse(mens.belongsToTennisTour(.wta))

        let womens = match(league: .wta, draw: "womens-singles")
        XCTAssertTrue(womens.belongsToTennisTour(.wta))
        XCTAssertFalse(womens.belongsToTennisTour(.atp))
    }

    func testMixedDoublesAppearsUnderBothTours() {
        let mixed = match(league: .atp, draw: "mixed-doubles")
        XCTAssertTrue(mixed.isMixedDoubles)
        XCTAssertTrue(mixed.belongsToTennisTour(.atp))
        XCTAssertTrue(mixed.belongsToTennisTour(.wta))
    }

    /// A game with no draw (older cached payload, or a non-ESPN source) must still land
    /// somewhere rather than vanishing from both tabs.
    func testMatchWithoutDrawFallsBackToItsLeague() {
        let g = match(league: .wta, draw: nil)
        XCTAssertFalse(g.isMixedDoubles)
        XCTAssertTrue(g.belongsToTennisTour(.wta))
        XCTAssertFalse(g.belongsToTennisTour(.atp))
    }

    // MARK: - Ingest

    /// The regression itself: the women's draw served on the ATP board must still come
    /// out as WTA.
    func testWomensDrawOnTheATPBoardIsTaggedWTA() throws {
        let board = try scoreboard(slug: "atp", draws: [
            ("mens-singles",   ["101"]),
            ("womens-singles", ["201"]),
            ("mixed-doubles",  ["301"]),
        ])
        let event = try XCTUnwrap(LiveEvent(events: board, league: .atp))
        let byID = Dictionary(uniqueKeysWithValues: event.events.compactMap { g in
            g.idEvent.map { ($0, g) }
        })

        XCTAssertEqual(byID["101"]?.idLeague, "\(Leagues.atp.rawValue)")
        XCTAssertEqual(byID["201"]?.idLeague, "\(Leagues.wta.rawValue)", "women's draw mis-tagged")
        XCTAssertEqual(byID["301"]?.drawSlug, "mixed-doubles")
        XCTAssertEqual(byID["201"]?.drawSlug, "womens-singles")
    }

    /// Both boards produce identical rows for a combined slam, so de-duplicating by
    /// event ID is lossless — which is what makes the ingest-side dedup safe.
    func testBothBoardsProduceIdenticalRowsForACombinedDraw() throws {
        let draws = [("mens-singles", ["101"]), ("womens-singles", ["201"])]
        let fromATP = try XCTUnwrap(LiveEvent(events: try scoreboard(slug: "atp", draws: draws), league: .atp))
        let fromWTA = try XCTUnwrap(LiveEvent(events: try scoreboard(slug: "wta", draws: draws), league: .wta))

        XCTAssertEqual(fromATP.events.map(\.idEvent), fromWTA.events.map(\.idEvent))
        XCTAssertEqual(fromATP.events.map(\.idLeague), fromWTA.events.map(\.idLeague))
        XCTAssertEqual(fromATP.events, fromWTA.events)
    }

    // MARK: - Fixture

    /// Mirrors the real ESPN tennis shape: tournament event → groupings → competitions.
    private func scoreboard(slug: String, draws: [(String, [String])]) throws -> Scoreboard {
        func competitor(_ id: String, _ name: String, _ homeAway: String) -> String {
            #"{"id":"\#(id)","uid":"a\#(id)","type":"athlete","homeAway":"\#(homeAway)","athlete":{"id":"\#(id)","displayName":"\#(name)"}}"#
        }
        let groupings = draws.map { drawSlug, ids in
            let comps = ids.map { id in
                #"{"id":"\#(id)","uid":"c\#(id)","date":"2026-09-07T15:00Z","competitors":[\#(competitor(id + "h", "Home " + id, "home")),\#(competitor(id + "a", "Away " + id, "away"))]}"#
            }.joined(separator: ",")
            return #"{"grouping":{"slug":"\#(drawSlug)"},"competitions":[\#(comps)]}"#
        }.joined(separator: ",")
        let json = #"""
        {"leagues":[{"id":"850","slug":"\#(slug)"}],
         "events":[{"id":"189-2026","uid":"u","date":"2026-08-24T04:00Z","name":"US Open","groupings":[\#(groupings)]}]}
        """#
        return try JSONDecoder().decode(Scoreboard.self, from: Data(json.utf8))
    }
}
