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
    /// uses 1.5s.
    private func makeCache() -> LiveFrameCache {
        LiveFrameCache(refreshInterval: 0)
    }

    func testFirstFrameIsFull() async throws {
        let cache = makeCache()
        let source = snapshot([("1", "10", "8")])

        let result = await cache.next(after: nil, fetch: { source })

        let frame = try decode(try XCTUnwrap(result).payload)
        XCTAssertEqual(frame.kind, .full)
        XCTAssertEqual(frame.live.nba?.events.count, 1)
    }

    func testSecondFrameIsADeltaCarryingOnlyChangedGames() async throws {
        let cache = makeCache()
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
        let cache = makeCache()
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
        let cache = makeCache()
        let source = snapshot([("1", "10", "8")])

        let firstResult = await cache.next(after: nil, fetch: { source })
        let first = try XCTUnwrap(firstResult)
        let second = await cache.next(after: first.seq, fetch: { source })

        XCTAssertNil(second)
    }

    /// A client more than one sequence behind — its previous send outran a tick — can't
    /// apply the newest delta, so it must be resynced rather than quietly skewed.
    func testClientMoreThanOneSequenceBehindGetsFullFrame() async throws {
        let cache = makeCache()
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
        let cache = makeCache()
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
        let cache = makeCache()
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
        let cache = makeCache()
        let source = snapshot([("1", "10", "8"), ("2", "3", "5")])

        let unwrapped = await cache.next(after: nil, fetch: { source })
        let result = try XCTUnwrap(unwrapped)
        let frame = try decode(result.payload)

        XCTAssertEqual(frame.live.nba?.events.map(\.idEvent), ["1", "2"])
        XCTAssertEqual(frame.live.nba?.events.first?.intHomeScore, "10")
    }
}
