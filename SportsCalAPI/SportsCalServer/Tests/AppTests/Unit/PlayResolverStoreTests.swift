@testable import App
import XCTest
import Logging
import SportsCalModel

/// `/plays` input validation and the hash-backed ESPN event map (with migration
/// from the legacy JSON blob).
final class PlayResolverStoreTests: XCTestCase {
    private let logger = Logger(label: "test.play-resolver")

    func test_eventIDValidation() {
        XCTAssertTrue(PlayResolver.isValidEventID("401772938"))
        XCTAssertTrue(PlayResolver.isValidEventID("evt-1_a"))
        XCTAssertFalse(PlayResolver.isValidEventID(""))
        XCTAssertFalse(PlayResolver.isValidEventID("1&league=x"))
        XCTAssertFalse(PlayResolver.isValidEventID("../../x"))
        XCTAssertFalse(PlayResolver.isValidEventID(String(repeating: "1", count: 65)))
        XCTAssertFalse(PlayResolver.isValidEventID("１２３"), "non-ASCII digits rejected")
    }

    func test_sportLeagueValidation() {
        XCTAssertTrue(PlayResolver.isKnownESPNPath(sport: "basketball", league: "nba"))
        XCTAssertTrue(PlayResolver.isKnownESPNPath(sport: "football", league: "nfl"))
        XCTAssertTrue(PlayResolver.isKnownESPNPath(sport: "football", league: "college-football"))
        XCTAssertTrue(PlayResolver.isKnownESPNPath(sport: "soccer", league: "eng.1"))
        XCTAssertTrue(PlayResolver.isKnownESPNPath(sport: "baseball", league: "mlb"))
        XCTAssertFalse(PlayResolver.isKnownESPNPath(sport: "soccer", league: "nba"), "sport must match the league")
        XCTAssertFalse(PlayResolver.isKnownESPNPath(sport: "basketball", league: "made-up"))
        XCTAssertFalse(PlayResolver.isKnownESPNPath(sport: "../x", league: "nba"))
    }

    func test_eventMap_migratesLegacyBlob_andLooksUpByField() async throws {
        let kv = RedisCapableKV()
        let legacy = ["t1": ESPNEventMapping(espnEventID: "e1", sport: "basketball", league: "nba")]
        try await kv.setJSON("ESPN-Event-Map", value: legacy, ttl: nil)

        // Before migration, the legacy blob still answers.
        let before = await ESPNEventMapStore.lookup(eventID: "t1", kv: kv, isDebug: false)
        XCTAssertEqual(before?.espnEventID, "e1")

        await ESPNEventMapStore.record(
            ["t2": ESPNEventMapping(espnEventID: "e2", sport: "hockey", league: "nhl")],
            kv: kv, isDebug: false, logger: logger
        )

        let legacyExists = try await kv.exists("ESPN-Event-Map")
        XCTAssertFalse(legacyExists, "the legacy blob is deleted once migrated")
        let t1 = await ESPNEventMapStore.lookup(eventID: "t1", kv: kv, isDebug: false)
        let t2 = await ESPNEventMapStore.lookup(eventID: "t2", kv: kv, isDebug: false)
        XCTAssertEqual(t1?.espnEventID, "e1")
        XCTAssertEqual(t2?.league, "nhl")
        let missing = await ESPNEventMapStore.lookup(eventID: "t3", kv: kv, isDebug: false)
        XCTAssertNil(missing)
    }

    func test_eventMap_storeWithoutHashes_keepsLegacyFormat() async throws {
        let kv = InMemoryKeyValueStore()
        await ESPNEventMapStore.record(
            ["t1": ESPNEventMapping(espnEventID: "e1", sport: "basketball", league: "nba")],
            kv: kv, isDebug: false, logger: logger
        )
        let found = await ESPNEventMapStore.lookup(eventID: "t1", kv: kv, isDebug: false)
        XCTAssertEqual(found?.espnEventID, "e1")
    }
}
