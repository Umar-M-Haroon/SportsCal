import XCTest
@testable import SportsCalModel

/// Pins the behavior of `Team.shortCode`, the centralized abbreviation fallback that
/// replaced the brittle `String(name.prefix(3)).uppercased()` pattern (which produced
/// "NEW" for "New York Knicks").
final class TeamShortCodeTests: XCTestCase {

    func testPrefersRealAbbreviation() {
        XCTAssertEqual(Team.shortCode(strTeamShort: "NYK", name: "New York Knicks"), "NYK")
        // The Knicks' 2-letter ESPN code is corrected by the curated override.
        XCTAssertEqual(Team.shortCode(strTeamShort: "NY", name: "New York Knicks", idTeam: "134862"), "NYK")
    }

    /// ESPN's real NFL codes are 2 letters for seven teams. They were re-derived from the
    /// name as "KCC", "SF4", "GBP" in the box score and the Teams list, while the Games
    /// feed showed the raw "KC"/"SF"/"GB".
    func testKeepsESPNTwoLetterNFLCodes() {
        let nfl: [(id: String, name: String, code: String)] = [
            ("134931", "Kansas City Chiefs", "KC"),
            ("134948", "San Francisco 49ers", "SF"),
            ("134940", "Green Bay Packers", "GB"),
            ("134932", "Las Vegas Raiders", "LV"),
            ("134920", "New England Patriots", "NE"),
            ("134944", "New Orleans Saints", "NO"),
            ("134945", "Tampa Bay Buccaneers", "TB"),
            ("135907", "Los Angeles Rams", "LAR"),
            ("135908", "Los Angeles Chargers", "LAC"),
            ("134935", "New York Giants", "NYG"),
            ("134921", "New York Jets", "NYJ"),
            ("134928", "Jacksonville Jaguars", "JAX"),
            ("134937", "Washington Commanders", "WSH"),
        ]
        for team in nfl {
            XCTAssertEqual(Team.shortCode(strTeamShort: team.code, name: team.name, idTeam: team.id), team.code, team.name)
            XCTAssertEqual(Team(idTeam: team.id, strTeam: team.name, strTeamShort: team.code).shortCode, team.code, team.name)
        }
    }

    /// Same class of bug in the other leagues: MLB "KC"/"SF"/"SD"/"TB" and the Utah
    /// teams' "UTAH" (NBA Jazz, NHL Mammoth) are ESPN's codes, not "KCR"/"UJA"/"UMA".
    func testKeepsOtherLeaguesNonTriCodes() {
        XCTAssertEqual(Team.shortCode(strTeamShort: "KC", name: "Kansas City Royals"), "KC")
        XCTAssertEqual(Team.shortCode(strTeamShort: "SD", name: "San Diego Padres"), "SD")
        XCTAssertEqual(Team.shortCode(strTeamShort: "UTAH", name: "Utah Jazz"), "UTAH")
        XCTAssertEqual(Team.shortCode(strTeamShort: "UTAH", name: "Utah Mammoth"), "UTAH")
    }

    /// Junk short codes still fall back to the name.
    func testRejectsMalformedCodes() {
        XCTAssertEqual(Team.shortCode(strTeamShort: "Worcester Ci", name: "Worcester City"), "WCI")
        XCTAssertEqual(Team.shortCode(strTeamShort: "CF ", name: "Calamocha"), "CAL")
        XCTAssertEqual(Team.shortCode(strTeamShort: "K", name: "Kansas City Chiefs"), "KCC")
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

    func testSingleWordFallsBackToFirstThreeLetters() {
        XCTAssertEqual(Team.shortCode(strTeamShort: nil, name: "Arsenal"), "ARS")
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

    /// TheSportsDB sends "" for a minor team's missing fields; decoding them as nil lets views
    /// fall back to initials and the placeholder badge instead of rendering blanks.
    func testDecodingTreatsBlankFieldsAsMissing() throws {
        let json = #"{"idTeam":"999","strTeam":"London Lions","strTeamShort":"","strTeamBadge":" ","strAlternate":""}"#
        let team = try JSONDecoder().decode(Team.self, from: Data(json.utf8))
        XCTAssertEqual(team.strTeam, "London Lions")
        XCTAssertNil(team.strTeamShort)
        XCTAssertNil(team.strTeamBadge)
        XCTAssertNil(team.strAlternate)
        XCTAssertEqual(Team.shortCode(strTeamShort: team.strTeamShort, name: team.strTeam ?? ""), "LLI")
    }
}
