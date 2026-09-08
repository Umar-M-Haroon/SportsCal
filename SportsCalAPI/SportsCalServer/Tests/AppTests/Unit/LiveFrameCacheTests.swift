import XCTest
import SportsCalModel
@testable import App

/// Covers the sequencing that decides whether a `/ws` client is handed a small delta or
/// a fresh full snapshot.
///
/// Getting this wrong is silent in both directions: hand out a delta the client can't
/// apply and its scores freeze at the last full frame; hand out a full frame every tick
/// and the ~4.76 MB payload this was built to eliminate comes straight back.
final class LiveFrameCacheTests: XCTestCase {

    private func snapshot(_ games: [(id: String, home: String, away: String)]) -> String {
        let events = games.map { g in
            #"{"idEvent":"\#(g.id)","idLeague":"4387","strHomeTeam":"H","strAwayTeam":"A","intHomeScore":"\#(g.home)","intAwayScore":"\#(g.away)","strStatus":"in"}"#
        }.joined(separator: ",")
        return #"{"nba":{"events":[\#(events)]}}"#
    }

    private func decode(_ payload: String) throws -> LiveFrame {
        try JSONDecoder().decode(LiveFrame.self, from: Data(payload.utf8))
    }

    /// Zero interval so every `next` call re-reads the source; the production instance
    /// uses 1.5s. Subscribed, because the cache only pays for the diff while a v2 client
    /// is connected — see `testWithoutSubscribersOnlyFullFramesAreProduced`.
    private func makeCache() async -> LiveFrameCache {
        let cache = LiveFrameCache(refreshInterval: 0)
        await cache.subscribeToDeltas()
        return cache
    }

    func testFirstFrameIsFull() async throws {
        let cache = await makeCache()
        let source = snapshot([("1", "10", "8")])

        let result = await cache.next(after: nil, fetch: { source })

        let frame = try decode(try XCTUnwrap(result).payload)
        XCTAssertEqual(frame.kind, .full)
        XCTAssertEqual(frame.live.nba?.events.count, 1)
    }

    func testSecondFrameIsADeltaCarryingOnlyChangedGames() async throws {
        let cache = await makeCache()
        var source = snapshot([("1", "10", "8"), ("2", "3", "5")])

        let firstResult = await cache.next(after: nil, fetch: { source })
        let first = try XCTUnwrap(firstResult)
        source = snapshot([("1", "10", "8"), ("2", "3", "7")])
        let secondResult = await cache.next(after: first.seq, fetch: { source })
        let second = try XCTUnwrap(secondResult)

        let frame = try decode(second.payload)
        XCTAssertEqual(frame.kind, .delta)
        XCTAssertEqual(frame.live.nba?.events.map(\.idEvent), ["2"])
        XCTAssertEqual(frame.live.nba?.events.first?.intAwayScore, "7")
    }

    /// The whole point: a one-score change must not put the other games on the wire.
    func testDeltaIsSubstantiallySmallerThanFullFrame() async throws {
        let cache = await makeCache()
        let many = (1...200).map { (id: "\($0)", home: "0", away: "0") }
        var source = snapshot(many)

        let firstResult = await cache.next(after: nil, fetch: { source })
        let first = try XCTUnwrap(firstResult)
        var changed = many
        changed[7] = (id: "8", home: "1", away: "0")
        source = snapshot(changed)
        let secondResult = await cache.next(after: first.seq, fetch: { source })
        let second = try XCTUnwrap(secondResult)

        XCTAssertLessThan(second.payload.utf8.count * 10, first.payload.utf8.count)
    }

    func testUnchangedSourceYieldsNothingToSend() async throws {
        let cache = await makeCache()
        let source = snapshot([("1", "10", "8")])

        let firstResult = await cache.next(after: nil, fetch: { source })
        let first = try XCTUnwrap(firstResult)
        let second = await cache.next(after: first.seq, fetch: { source })

        XCTAssertNil(second)
    }

    /// A client more than one sequence behind — its previous send outran a tick — can't
    /// apply the newest delta, so it must be resynced rather than quietly skewed.
    func testClientMoreThanOneSequenceBehindGetsFullFrame() async throws {
        let cache = await makeCache()
        var source = snapshot([("1", "10", "8")])
        let firstResult = await cache.next(after: nil, fetch: { source })
        let first = try XCTUnwrap(firstResult)

        source = snapshot([("1", "11", "8")])
        _ = await cache.next(after: first.seq, fetch: { source })
        source = snapshot([("1", "12", "8")])
        let thirdResult = await cache.next(after: first.seq, fetch: { source })
        let third = try XCTUnwrap(thirdResult)

        let frame = try decode(third.payload)
        XCTAssertEqual(frame.kind, .full)
        XCTAssertEqual(frame.live.nba?.events.first?.intHomeScore, "12")
    }

    func testGameLeavingSnapshotIsReportedAsRemoved() async throws {
        let cache = await makeCache()
        var source = snapshot([("1", "10", "8"), ("2", "3", "5")])
        let firstResult = await cache.next(after: nil, fetch: { source })
        let first = try XCTUnwrap(firstResult)

        source = snapshot([("1", "10", "8")])
        let secondResult = await cache.next(after: first.seq, fetch: { source })
        let second = try XCTUnwrap(secondResult)

        let frame = try decode(second.payload)
        XCTAssertEqual(frame.removed, ["2"])
    }

    /// The invariant the client relies on: applying each delta in turn to the first full
    /// frame reproduces what the server actually holds.
    func testReplayingDeltasReproducesTheLatestSnapshot() async throws {
        let cache = await makeCache()
        var source = snapshot([("1", "0", "0"), ("2", "0", "0"), ("3", "0", "0")])
        let firstResult = await cache.next(after: nil, fetch: { source })
        let first = try XCTUnwrap(firstResult)
        var state = try decode(first.payload).live
        var seq = first.seq

        for scores in [("1", "0"), ("2", "0"), ("3", "1")] {
            source = snapshot([("1", scores.0, scores.1), ("2", "0", "0"), ("3", "0", "0")])
            guard let next = await cache.next(after: seq, fetch: { source }) else { continue }
            let frame = try decode(next.payload)
            state = frame.kind == .full
                ? frame.live
                : state.applying(delta: frame.live, removed: frame.removed)
            seq = next.seq
        }

        XCTAssertEqual(state.nba?.events.count, 3)
        XCTAssertEqual(state.nba?.events.first(where: { $0.idEvent == "1" })?.intHomeScore, "3")
        XCTAssertEqual(state.nba?.events.first(where: { $0.idEvent == "1" })?.intAwayScore, "1")
    }

    /// The full frame is produced by splicing the cached Redis string into an envelope
    /// rather than decoding and re-encoding it, so it has to stay valid JSON that
    /// round-trips to the same games.
    func testSplicedFullFrameRoundTrips() async throws {
        let cache = await makeCache()
        let source = snapshot([("1", "10", "8"), ("2", "3", "5")])

        let unwrapped = await cache.next(after: nil, fetch: { source })
        let result = try XCTUnwrap(unwrapped)
        let frame = try decode(result.payload)

        XCTAssertEqual(frame.live.nba?.events.map(\.idEvent), ["1", "2"])
        XCTAssertEqual(frame.live.nba?.events.first?.intHomeScore, "10")
    }

    // MARK: - Cost gating

    /// With nobody on the delta protocol the cache must not pay for the diff — that work
    /// is a full decode of the multi-MB snapshot plus an encode, synchronously on this
    /// actor, which every v1 client's `current()` also waits on.
    func testWithoutSubscribersOnlyFullFramesAreProduced() async throws {
        let cache = LiveFrameCache(refreshInterval: 0)   // deliberately unsubscribed
        var source = snapshot([("1", "10", "8"), ("2", "3", "5")])

        let firstResult = await cache.next(after: nil, fetch: { source })
        let first = try XCTUnwrap(firstResult)
        source = snapshot([("1", "10", "8"), ("2", "3", "7")])
        let secondResult = await cache.next(after: first.seq, fetch: { source })
        let second = try XCTUnwrap(secondResult)

        XCTAssertEqual(try decode(second.payload).kind, .full)
    }

    /// A client arriving after a quiet period must be resynced from a full frame, not
    /// handed a delta against a baseline the cache stopped maintaining.
    func testSubscriberArrivingLateGetsFullFrameFirst() async throws {
        let cache = LiveFrameCache(refreshInterval: 0)
        var source = snapshot([("1", "10", "8")])
        _ = await cache.next(after: nil, fetch: { source })

        await cache.subscribeToDeltas()
        source = snapshot([("1", "11", "8")])
        let resultRaw = await cache.next(after: nil, fetch: { source })
        let result = try XCTUnwrap(resultRaw)

        XCTAssertEqual(try decode(result.payload).kind, .full)
    }

    // MARK: - Enrichment

    /// World Cup enrichment is the bracket plus scorers plus squads. Stamping it into
    /// every 1.5s delta would undo most of the payload reduction during exactly the
    /// tournament this was built for.
    func testUnchangedEnrichmentIsOmittedFromDeltas() async throws {
        let cache = await makeCache()
        let standings = #"{"driverStandings":[{"position":1,"driverName":"Verstappen","constructorName":"Red Bull","points":310,"wins":9}],"constructorStandings":[]}"#
        func withStandings(_ games: String) -> String {
            #"{"nba":{"events":[\#(games)]},"f1Standings":\#(standings)}"#
        }
        let game1 = #"{"idEvent":"1","idLeague":"4387","strHomeTeam":"H","strAwayTeam":"A","intHomeScore":"10","strStatus":"in"}"#
        let game1b = #"{"idEvent":"1","idLeague":"4387","strHomeTeam":"H","strAwayTeam":"A","intHomeScore":"11","strStatus":"in"}"#

        var source = withStandings(game1)
        let firstRaw = await cache.next(after: nil, fetch: { source })
        let first = try XCTUnwrap(firstRaw)
        source = withStandings(game1b)
        let secondRaw = await cache.next(after: first.seq, fetch: { source })
        let second = try XCTUnwrap(secondRaw)

        let frame = try decode(second.payload)
        XCTAssertEqual(frame.kind, .delta)
        XCTAssertNil(frame.live.f1Standings, "unchanged enrichment should not ride along")
    }

    /// The complement: when it *does* change it has to be sent, or a v2 client would
    /// never see updated standings.
    func testChangedEnrichmentIsCarried() async throws {
        let cache = await makeCache()
        func source(points: Int, score: String) -> String {
            let standings = #"{"driverStandings":[{"position":1,"driverName":"Verstappen","constructorName":"Red Bull","points":\#(points),"wins":9}],"constructorStandings":[]}"#
            let game = #"{"idEvent":"1","idLeague":"4387","strHomeTeam":"H","strAwayTeam":"A","intHomeScore":"\#(score)","strStatus":"in"}"#
            return #"{"nba":{"events":[\#(game)]},"f1Standings":\#(standings)}"#
        }

        var payload = source(points: 310, score: "10")
        let firstRaw = await cache.next(after: nil, fetch: { payload })
        let first = try XCTUnwrap(firstRaw)
        payload = source(points: 335, score: "11")
        let secondRaw = await cache.next(after: first.seq, fetch: { payload })
        let second = try XCTUnwrap(secondRaw)

        let frame = try decode(second.payload)
        XCTAssertEqual(frame.live.f1Standings?.driverStandings.first?.points, 335)
    }

    // MARK: - Change detection breadth

    /// A game whose leaders appear a few minutes in, with no score change, still has to
    /// reach the client — ESPN populates them late, and a score-only signature would
    /// leave the leaders panel empty for the whole session.
    func testNonScoreFieldChangeStillProducesADelta() async throws {
        let cache = await makeCache()
        let base = #"{"idEvent":"1","idLeague":"4387","strHomeTeam":"H","strAwayTeam":"A","intHomeScore":"10","strStatus":"in"}"#
        let withLeaders = #"{"idEvent":"1","idLeague":"4387","strHomeTeam":"H","strAwayTeam":"A","intHomeScore":"10","strStatus":"in","homeLeaders":[{"category":"points","categoryDisplay":"Points","playerName":"Player","displayValue":"22"}]}"#

        var source = #"{"nba":{"events":[\#(base)]}}"#
        let firstRaw = await cache.next(after: nil, fetch: { source })
        let first = try XCTUnwrap(firstRaw)
        source = #"{"nba":{"events":[\#(withLeaders)]}}"#
        let secondRaw = await cache.next(after: first.seq, fetch: { source })
        let second = try XCTUnwrap(secondRaw)

        let frame = try decode(second.payload)
        XCTAssertEqual(frame.kind, .delta)
        XCTAssertEqual(frame.live.nba?.events.first?.homeLeaders?.first?.playerName, "Player")
    }
}
