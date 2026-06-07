import XCTest
@testable import SportsCalModel

/// Pins the behavior of `Team.shortCode`, the centralized abbreviation fallback that
/// replaced the brittle `String(name.prefix(3)).uppercased()` pattern (which produced
/// "NEW" for "New York Knicks").
final class TeamShortCodeTests: XCTestCase {

    func testPrefersRealAbbreviation() {
        XCTAssertEqual(Team.shortCode(strTeamShort: "NYK", name: "New York Knicks"), "NYK")
        // A real (even 2-letter) code wins over derived initials.
        XCTAssertEqual(Team.shortCode(strTeamShort: "NY", name: "New York Knicks"), "NY")
    }

    func testDerivesInitialsWhenMissing() {
        // The bug case: nil/empty short code must NOT become "NEW".
        XCTAssertEqual(Team.shortCode(strTeamShort: nil, name: "New York Knicks"), "NYK")
        XCTAssertEqual(Team.shortCode(strTeamShort: "", name: "Los Angeles Lakers"), "LAL")
        XCTAssertEqual(Team.shortCode(strTeamShort: nil, name: "San Antonio Spurs"), "SAS")
    }

    func testCapsAtThreeInitials() {
        XCTAssertEqual(Team.shortCode(strTeamShort: nil, name: "Real Salt Lake City"), "RSL")
    }

    func testSingleWordFallsBackToName() {
        XCTAssertEqual(Team.shortCode(strTeamShort: nil, name: "Arsenal"), "ARSENAL")
    }

    func testInstanceHelper() {
        let team = Team(idTeam: "134862", strTeam: "New York Knicks", strTeamShort: nil)
        XCTAssertEqual(team.shortCode, "NYK")
    }

    /// Decoding applies the curated correction: the Knicks' stored 2-letter "NY"
    /// surfaces as the tricode "NYK" without a server redeploy.
    func testDecodeAppliesCanonicalOverride() throws {
        let json = #"{"idTeam":"134862","strTeam":"New York Knicks","strTeamShort":"NY"}"#.data(using: .utf8)!
        let team = try JSONDecoder().decode(Team.self, from: json)
        XCTAssertEqual(team.strTeamShort, "NYK")
    }

    func testDecodeLeavesNonOverriddenTeams() throws {
        let json = #"{"idTeam":"135252","strTeam":"Brooklyn Nets","strTeamShort":"BKN"}"#.data(using: .utf8)!
        let team = try JSONDecoder().decode(Team.self, from: json)
        XCTAssertEqual(team.strTeamShort, "BKN")
    }
}
