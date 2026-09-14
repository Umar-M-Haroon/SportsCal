import XCTest
@testable import Scoreline

/// Pins the token-sharing rules that let the widget and watch send an attested
/// credential they cannot mint themselves.
///
/// Neither store is a cache in the usual sense: the holder has no way to
/// refresh, so "expired" and "absent" have to mean the same thing. Handing a
/// widget a token that dies mid-flight is worse than handing it none, because
/// the request fails instead of falling back to the shared API key.
final class AttestTokenSharingTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(
            UserDefaults(suiteName: SharedAttestToken.suiteName),
            "App Group defaults unavailable — the test host is missing the group entitlement"
        )
        SharedAttestToken.clear()
    }

    override func tearDown() {
        SharedAttestToken.clear()
    }

    // MARK: - Availability

    func testNoTokenWhenNothingStored() {
        XCTAssertNil(SharedAttestToken.current())
    }

    func testStoredTokenIsReadableWhileFresh() {
        SharedAttestToken.store("tok-abc", expiresAt: Date().addingTimeInterval(900))
        XCTAssertEqual(SharedAttestToken.current(), "tok-abc")
    }

    func testExpiredTokenReadsAsAbsent() {
        SharedAttestToken.store("tok-stale", expiresAt: Date().addingTimeInterval(-1))
        XCTAssertNil(SharedAttestToken.current(), "an expired token must not be sent — it would 401 instead of falling back")
    }

    /// The widget cannot refresh, so a token about to lapse is useless: it may
    /// well expire between being read and reaching the server.
    func testTokenInsideTheExpiryMarginReadsAsAbsent() {
        let now = Date()
        SharedAttestToken.store("tok-edge", expiresAt: now.addingTimeInterval(10))
        XCTAssertNil(SharedAttestToken.current(now: now))

        SharedAttestToken.store("tok-ok", expiresAt: now.addingTimeInterval(120))
        XCTAssertEqual(SharedAttestToken.current(now: now), "tok-ok")
    }

    func testClearRemovesTheToken() {
        SharedAttestToken.store("tok-abc", expiresAt: Date().addingTimeInterval(900))
        SharedAttestToken.clear()
        XCTAssertNil(SharedAttestToken.current())
    }

    /// Signing out or a server-ordered re-attest must not leave a usable
    /// credential sitting in the App Group for the widget to keep sending.
    func testClearedTokenIsNotResurrectedByAFreshRead() {
        SharedAttestToken.store("tok-abc", expiresAt: Date().addingTimeInterval(900))
        SharedAttestToken.clear()
        XCTAssertNil(defaults.string(forKey: "attest.sharedToken"))
        XCTAssertNil(SharedAttestToken.current())
    }

    // MARK: - Overwrite semantics

    func testStoringReplacesThePreviousToken() {
        SharedAttestToken.store("tok-old", expiresAt: Date().addingTimeInterval(60))
        SharedAttestToken.store("tok-new", expiresAt: Date().addingTimeInterval(900))
        XCTAssertEqual(SharedAttestToken.current(), "tok-new")
    }

    /// A refresh that somehow lands with a shorter life must still be honoured
    /// verbatim — the expiry is the server's statement, not ours to widen.
    func testExpiryFollowsTheMostRecentStore() {
        let now = Date()
        SharedAttestToken.store("tok-long", expiresAt: now.addingTimeInterval(900))
        SharedAttestToken.store("tok-short", expiresAt: now.addingTimeInterval(-5))
        XCTAssertNil(SharedAttestToken.current(now: now))
    }
}
