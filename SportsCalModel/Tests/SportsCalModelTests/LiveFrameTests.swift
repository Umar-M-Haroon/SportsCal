import XCTest
@testable import SportsCalModel

/// Pins the delta-frame semantics the live WebSocket depends on.
///
/// The client's whole live path now assumes that applying a `delta` to the snapshot it
/// already holds yields exactly what a `full` frame would have contained. If that stops
/// being true, scores silently freeze or stale games linger — neither of which surfaces
/// as a crash, so it has to be pinned here.
final class LiveFrameTests: XCTestCase {

    private func game(
        id: String,
        home: String = "Home",
        away: String = "Away",
        homeScore: String? = nil,
        awayScore: String? = nil,
        status: String? = "in",
        league: String? = "4387"
    ) -> Game {
        Game(
            idEvent: id,
            idLeague: league,
            strHomeTeam: home,
            strAwayTeam: away,
            intHomeScore: homeScore,
            intAwayScore: awayScore,
            strStatus: status,
            isoDate: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }

    // MARK: - Merging

    func testDeltaReplacesGameByEventID() {
        let base = LiveScore(nba: LiveEvent(events: [
            game(id: "1", homeScore: "10", awayScore: "8"),
            game(id: "2", homeScore: "3", awayScore: "5"),
        ]))
        let delta = LiveScore(nba: LiveEvent(events: [
            game(id: "2", homeScore: "3", awayScore: "7"),
        ]))

        let merged = base.applying(delta: delta, removed: nil)

        XCTAssertEqual(merged.nba?.events.count, 2)
        XCTAssertEqual(merged.nba?.events.first(where: { $0.idEvent == "1" })?.intAwayScore, "8")
        XCTAssertEqual(merged.nba?.events.first(where: { $0.idEvent == "2" })?.intAwayScore, "7")
    }

    func testDeltaPreservesOrderOfExistingGames() {
        let base = LiveScore(nba: LiveEvent(events: [
            game(id: "1"), game(id: "2"), game(id: "3"),
        ]))
        let delta = LiveScore(nba: LiveEvent(events: [game(id: "2", homeScore: "99")]))

        let merged = base.applying(delta: delta, removed: nil)

        XCTAssertEqual(merged.nba?.events.map(\.idEvent), ["1", "2", "3"])
    }

    func testDeltaAppendsUnseenGame() {
        let base = LiveScore(nba: LiveEvent(events: [game(id: "1")]))
        let delta = LiveScore(nba: LiveEvent(events: [game(id: "2")]))

        let merged = base.applying(delta: delta, removed: nil)

        XCTAssertEqual(merged.nba?.events.map(\.idEvent), ["1", "2"])
    }

    func testRemovedIDsAreDropped() {
        let base = LiveScore(nba: LiveEvent(events: [game(id: "1"), game(id: "2")]))

        let merged = base.applying(delta: LiveScore(), removed: ["1"])

        XCTAssertEqual(merged.nba?.events.map(\.idEvent), ["2"])
    }

    func testDeltaOnlyTouchesItsOwnSport() {
        let base = LiveScore(
            nba: LiveEvent(events: [game(id: "n1", homeScore: "10")]),
            soccer: LiveEvent(events: [game(id: "s1", homeScore: "1")])
        )
        let delta = LiveScore(soccer: LiveEvent(events: [game(id: "s1", homeScore: "2")]))

        let merged = base.applying(delta: delta, removed: nil)

        XCTAssertEqual(merged.nba?.events.first?.intHomeScore, "10")
        XCTAssertEqual(merged.soccer?.events.first?.intHomeScore, "2")
    }

    /// Absent enrichment on a delta means "unchanged", not "cleared" — the server only
    /// puts it on the wire when it actually moved.
    func testAbsentEnrichmentIsPreservedNotCleared() {
        let standings = F1Standings(driverStandings: [
            F1DriverStanding(position: 1, driverName: "Verstappen", constructorName: "Red Bull", points: 310, wins: 9)
        ])
        let base = LiveScore(racing: LiveEvent(events: [game(id: "r1")]), f1Standings: standings)

        let merged = base.applying(delta: LiveScore(), removed: nil)

        XCTAssertEqual(merged.f1Standings?.driverStandings.first?.driverName, "Verstappen")
    }

    /// A bucket the base never had shouldn't be conjured into existence by an empty
    /// delta — nil and empty read differently downstream.
    func testEmptyDeltaDoesNotMaterializeMissingBuckets() {
        let base = LiveScore(nba: LiveEvent(events: [game(id: "1")]))

        let merged = base.applying(delta: LiveScore(), removed: nil)

        XCTAssertNil(merged.soccer)
        XCTAssertNil(merged.golf)
    }

    /// The end-to-end invariant: base + delta == the full frame the server would have sent.
    func testMergedDeltaMatchesEquivalentFullFrame() {
        let base = LiveScore(nba: LiveEvent(events: [
            game(id: "1", homeScore: "10", awayScore: "8"),
            game(id: "2", homeScore: "3", awayScore: "5"),
            game(id: "3", homeScore: "0", awayScore: "0"),
        ]))
        let full = LiveScore(nba: LiveEvent(events: [
            game(id: "1", homeScore: "10", awayScore: "8"),
            game(id: "2", homeScore: "3", awayScore: "7"),
        ]))
        let delta = LiveScore(nba: LiveEvent(events: [game(id: "2", homeScore: "3", awayScore: "7")]))

        let merged = base.applying(delta: delta, removed: ["3"])

        XCTAssertEqual(merged.nba?.events.count, full.nba?.events.count)
        XCTAssertEqual(
            Set(merged.nba?.events.map(\.idEvent) ?? []),
            Set(full.nba?.events.map(\.idEvent) ?? [])
        )
        XCTAssertEqual(merged.nba?.events.first(where: { $0.idEvent == "2" })?.intAwayScore, "7")
    }

    // MARK: - Signatures

    func testSignatureChangesWhenScoreChanges() {
        let before = LiveScore(nba: LiveEvent(events: [game(id: "1", homeScore: "10")]))
        let after = LiveScore(nba: LiveEvent(events: [game(id: "1", homeScore: "11")]))

        XCTAssertNotEqual(before.contentSignature, after.contentSignature)
    }

    func testSignatureStableForIdenticalSnapshots() {
        let a = LiveScore(nba: LiveEvent(events: [game(id: "1", homeScore: "10")]))
        let b = LiveScore(nba: LiveEvent(events: [game(id: "1", homeScore: "10")]))

        XCTAssertEqual(a.contentSignature, b.contentSignature)
    }

    func testSignatureChangesWhenGameLeaves() {
        let before = LiveScore(nba: LiveEvent(events: [game(id: "1"), game(id: "2")]))
        let after = LiveScore(nba: LiveEvent(events: [game(id: "1")]))

        XCTAssertNotEqual(before.contentSignature, after.contentSignature)
    }

    // MARK: - Envelope round-trip

    func testEnvelopeRoundTrips() throws {
        let frame = LiveFrame(
            seq: 7,
            kind: .delta,
            live: LiveScore(nba: LiveEvent(events: [game(id: "1", homeScore: "4")])),
            removed: ["9"]
        )
        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(LiveFrame.self, from: data)

        XCTAssertEqual(decoded.seq, 7)
        XCTAssertEqual(decoded.kind, .delta)
        XCTAssertEqual(decoded.removed, ["9"])
        XCTAssertEqual(decoded.live.nba?.events.first?.intHomeScore, "4")
    }

    /// The client probes for the envelope before falling back to a bare `LiveScore`.
    /// That order only works if a bare snapshot fails to decode as an envelope — if it
    /// succeeded, every frame from an old server would be read as an empty delta.
    func testBareLiveScoreDoesNotDecodeAsEnvelope() throws {
        let bare = LiveScore(nba: LiveEvent(events: [game(id: "1")]))
        let data = try JSONEncoder().encode(bare)

        XCTAssertNil(try? JSONDecoder().decode(LiveFrame.self, from: data))
    }

    /// The idle heartbeat the server sends v2 clients must parse, and must clear state
    /// rather than merge into it.
    func testHeartbeatFrameParsesAsEmptyFullFrame() throws {
        let data = #"{"seq":0,"kind":"full","live":{}}"#.data(using: .utf8)!
        let frame = try JSONDecoder().decode(LiveFrame.self, from: data)

        XCTAssertEqual(frame.kind, .full)
        XCTAssertNil(frame.live.nba)
    }
}

/// `Game.id` used to return a fresh `UUID` whenever `idEvent` was nil, which broke every
/// caller that assumed identity was stable across reads.
final class GameIdentityTests: XCTestCase {

    private func gameWithoutEventID() -> Game {
        Game(
            idLeague: "4387",
            strHomeTeam: "Knicks",
            strAwayTeam: "Hawks",
            strTimestamp: "2026-05-20T01:27:14Z",
            isoDate: nil
        )
    }

    func testIDIsStableAcrossReads() {
        let game = gameWithoutEventID()
        XCTAssertEqual(game.id, game.id)
    }

    func testIDIsStableAcrossIdenticalValues() {
        XCTAssertEqual(gameWithoutEventID().id, gameWithoutEventID().id)
    }

    func testDistinctFixturesGetDistinctIDs() {
        let a = gameWithoutEventID()
        let b = Game(
            idLeague: "4387",
            strHomeTeam: "Knicks",
            strAwayTeam: "Celtics",
            strTimestamp: "2026-05-20T01:27:14Z",
            isoDate: nil
        )
        XCTAssertNotEqual(a.id, b.id)
    }

    func testEventIDWinsWhenPresent() {
        let game = Game(idEvent: "12345", strHomeTeam: "A", strAwayTeam: "B", isoDate: nil)
        XCTAssertEqual(game.id, "12345")
    }

    /// An empty string is not a usable identity — it would collide across every game
    /// that has one.
    func testEmptyEventIDFallsBackToSyntheticID() {
        let game = Game(idEvent: "", idLeague: "4387", strHomeTeam: "A", strAwayTeam: "B", isoDate: nil)
        XCTAssertNotEqual(game.id, "")
        XCTAssertTrue(game.id.hasPrefix("syn:"))
    }
}
