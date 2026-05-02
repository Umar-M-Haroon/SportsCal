@testable import App
import XCTest
import SportsCalModel

/// APNSJob matches a registration to a live game either by eventID or — as a
/// fallback — by case-insensitive team-name pair. This is the highest-risk
/// silent-bug surface in the whole push pipeline, since a miss here simply
/// means "no update sent" with no user-visible error. Lock it down hard.
final class TeamMatchingTests: XCTestCase {

    // MARK: - eventID match

    func test_eventIDMatch_takesPrecedence_evenWhenTeamNamesWouldAlsoMatch() {
        let registration = APNSRegistration(eventID: "123", homeTeam: "Lakers", awayTeam: "Warriors")
        let events = [
            TestGameFactory.make(idEvent: "999", strHomeTeam: "Lakers", strAwayTeam: "Warriors"),
            TestGameFactory.make(idEvent: "123", strHomeTeam: "Different", strAwayTeam: "Teams")
        ]
        let match = APNSJob.matchEvent(events: events, registration: registration)
        XCTAssertEqual(match?.idEvent, "123")
        XCTAssertEqual(match?.strHomeTeam, "Different")
    }

    func test_eventIDMismatch_fallsThroughToTeamNameMatch() {
        let registration = APNSRegistration(eventID: "missing-id", homeTeam: "Lakers", awayTeam: "Warriors")
        let events = [
            TestGameFactory.make(idEvent: "999", strHomeTeam: "Lakers", strAwayTeam: "Warriors")
        ]
        let match = APNSJob.matchEvent(events: events, registration: registration)
        XCTAssertEqual(match?.idEvent, "999")
    }

    // MARK: - team-name fallback

    func test_teamNameMatch_caseInsensitive() {
        let registration = APNSRegistration(eventID: "missing", homeTeam: "LAKERS", awayTeam: "warriors")
        let events = [
            TestGameFactory.make(idEvent: "42", strHomeTeam: "Lakers", strAwayTeam: "Warriors")
        ]
        let match = APNSJob.matchEvent(events: events, registration: registration)
        XCTAssertEqual(match?.idEvent, "42")
    }

    func test_teamNameMatch_respectsHomeAwayOrder() {
        // A "Lakers @ Warriors" registration must NOT match a "Warriors @ Lakers" game.
        let registration = APNSRegistration(eventID: "x", homeTeam: "Lakers", awayTeam: "Warriors")
        let events = [
            TestGameFactory.make(idEvent: "42", strHomeTeam: "Warriors", strAwayTeam: "Lakers")
        ]
        XCTAssertNil(APNSJob.matchEvent(events: events, registration: registration))
    }

    func test_noMatch_whenTeamsDoNotAppearInAnyEvent() {
        let registration = APNSRegistration(eventID: "x", homeTeam: "Knicks", awayTeam: "Celtics")
        let events = [
            TestGameFactory.make(idEvent: "42", strHomeTeam: "Lakers", strAwayTeam: "Warriors")
        ]
        XCTAssertNil(APNSJob.matchEvent(events: events, registration: registration))
    }

    func test_legacyRegistration_withNilTeams_cannotFallBack() {
        // Pre-migration registrations stored only the event ID. If the eventID
        // doesn't match, there's nothing to fall back on and we must skip.
        let registration = APNSRegistration(eventID: "missing-id", homeTeam: nil, awayTeam: nil)
        let events = [
            TestGameFactory.make(idEvent: "999", strHomeTeam: "Lakers", strAwayTeam: "Warriors")
        ]
        XCTAssertNil(APNSJob.matchEvent(events: events, registration: registration))
    }

    func test_duplicateTeamNames_acrossLeagues_returnsFirstMatch() {
        // NFL Giants vs MLB Giants — unusual but real. Current implementation
        // returns the first match. Documenting that behavior here; if we later
        // disambiguate by league, update this test.
        let registration = APNSRegistration(eventID: "missing", homeTeam: "Giants", awayTeam: "Cowboys")
        let events = [
            TestGameFactory.make(idEvent: "nfl-1", strHomeTeam: "Giants", strAwayTeam: "Cowboys"),
            TestGameFactory.make(idEvent: "mlb-1", strHomeTeam: "Giants", strAwayTeam: "Cowboys")
        ]
        let match = APNSJob.matchEvent(events: events, registration: registration)
        XCTAssertEqual(match?.idEvent, "nfl-1")
    }

    // MARK: - decodeRegistration

    func test_decodeRegistration_parsesJSONFormat() {
        let raw = #"{"eventID":"abc","homeTeam":"Lakers","awayTeam":"Warriors"}"#
        let decoded = APNSJob.decodeRegistration(from: raw)
        XCTAssertEqual(decoded.eventID, "abc")
        XCTAssertEqual(decoded.homeTeam, "Lakers")
        XCTAssertEqual(decoded.awayTeam, "Warriors")
    }

    func test_decodeRegistration_fallsBackToLegacyPlainEventID() {
        // Pre-migration Redis entries store the bare event ID as a raw string,
        // not JSON. Job must still parse those — otherwise existing users silently
        // lose push updates the day we ship the new format.
        let decoded = APNSJob.decodeRegistration(from: "401584793")
        XCTAssertEqual(decoded.eventID, "401584793")
        XCTAssertNil(decoded.homeTeam)
        XCTAssertNil(decoded.awayTeam)
    }

    // MARK: - tokenFromKey

    func test_tokenFromKey_stripsProdPrefix() {
        XCTAssertEqual(APNSJob.tokenFromKey("APNS-abc123", prefix: "APNS-"), "abc123")
    }

    func test_tokenFromKey_stripsDebugPrefix() {
        XCTAssertEqual(APNSJob.tokenFromKey("debug-APNS-abc123", prefix: "debug-APNS-"), "abc123")
    }

    func test_tokenFromKey_leavesKeyUnchangedWhenPrefixMissing() {
        XCTAssertEqual(APNSJob.tokenFromKey("abc123", prefix: "APNS-"), "abc123")
    }
}
