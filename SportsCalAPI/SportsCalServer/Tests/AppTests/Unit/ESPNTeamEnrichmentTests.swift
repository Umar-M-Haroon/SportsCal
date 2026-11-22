@testable import App
import XCTest
import SportsCalModel

/// ESPNTeamFetchJob enriches TheSportsDB teams with ESPN's abbreviation and logo by
/// name. A loose suffix fallback once let a WNBA team claim a same-nickname team in
/// another sport: prod served the Detroit Red Wings as "DAL" with the Dallas Wings'
/// logo, and MLS Chicago Fire as "POR" with the Portland Fire's.
final class ESPNTeamEnrichmentTests: XCTestCase {

    private func espnTeam(id: String, display: String, name: String, abbreviation: String, logo: String) -> ESPNTeam {
        ESPNTeam(id: id, uid: nil, slug: nil, abbreviation: abbreviation, displayName: display,
                 shortDisplayName: name, name: name, nickname: nil, location: nil, color: nil,
                 alternateColor: nil, isActive: true, isAllStar: false,
                 logos: [Logo(href: logo, width: 500, height: 500, alt: "", rel: [], lastUpdated: "")], links: nil)
    }

    private func response(_ teams: [ESPNTeam]) -> TeamResponse {
        TeamResponse(sports: [Sport(id: nil, uid: nil, name: nil, slug: nil, leagues: [
            League(id: "1", uid: nil, name: nil, abbreviation: nil, shortName: nil, slug: nil,
                   teams: teams.map { TeamElement(team: $0) })
        ])])
    }

    func test_suffixFallback_doesNotCrossCities() {
        let tsdb = [
            Team(idTeam: "134832", strTeam: "Detroit Red Wings", strTeamShort: "DET"),
            Team(idTeam: "134154", strTeam: "Chicago Fire", strTeamShort: "CHI"),
        ]
        let espn: [Leagues: TeamResponse] = [
            .wnba: response([
                espnTeam(id: "3", display: "Dallas Wings", name: "Wings", abbreviation: "DAL", logo: "wnba/dal.png"),
                espnTeam(id: "1", display: "Portland Fire", name: "Fire", abbreviation: "POR", logo: "wnba/por.png"),
            ]),
        ]
        let (teams, idMap) = ESPNTeamFetchJob().returnUpdatedTeams(teams: tsdb, espnTeamsByLeague: espn)
        let byID = Dictionary(uniqueKeysWithValues: teams.map { ($0.idTeam!, $0) })
        XCTAssertEqual(byID["134832"]?.strTeamShort, "DET")
        XCTAssertNil(byID["134832"]?.strTeamBadge)
        XCTAssertNil(byID["134832"]?.strAlternate)
        XCTAssertEqual(byID["134154"]?.strTeamShort, "CHI")
        XCTAssertTrue(idMap.isEmpty)
    }

    func test_exactMatchBeatsAnotherLeaguesFallback() {
        let tsdb = [Team(idTeam: "134832", strTeam: "Detroit Red Wings", strTeamShort: nil)]
        // ESPN's displayName without the city, so the fallback has no city to check.
        let espn: [Leagues: TeamResponse] = [
            .wnba: response([espnTeam(id: "3", display: "Wings", name: "Wings", abbreviation: "DAL", logo: "wnba/dal.png")]),
            .nhl: response([espnTeam(id: "5", display: "Detroit Red Wings", name: "Red Wings", abbreviation: "DET", logo: "nhl/det.png")]),
        ]
        let (teams, idMap) = ESPNTeamFetchJob().returnUpdatedTeams(teams: tsdb, espnTeamsByLeague: espn)
        XCTAssertEqual(teams.first?.strTeamShort, "DET")
        XCTAssertEqual(teams.first?.strTeamBadge, "nhl/det.png")
        XCTAssertEqual(idMap, ["nhl:5": "134832"])
    }

    func test_suffixFallback_stillMatchesSameCity() {
        let tsdb = [Team(idTeam: "1", strTeam: "Deportivo Alavés", strTeamShort: nil)]
        let espn: [Leagues: TeamResponse] = [
            .La_Liga: response([espnTeam(id: "96", display: "Alavés", name: "Alavés", abbreviation: "ALA", logo: "soccer/96.png")]),
        ]
        let (teams, _) = ESPNTeamFetchJob().returnUpdatedTeams(teams: tsdb, espnTeamsByLeague: espn)
        XCTAssertEqual(teams.first?.strTeamShort, "ALA")
    }

    /// MLS: ESPN adds club suffixes TheSportsDB drops. These ten went unmatched on
    /// prod (Nov 2026), so they had no ESPN logo or ID mapping.
    func test_mlsClubSuffixesAndAliasesMatch() {
        let pairs: [(tsdbID: String, tsdb: String, espn: String, abbr: String)] = [
            ("135851", "Atlanta United", "Atlanta United FC", "ATL"),
            ("134154", "Chicago Fire", "Chicago Fire FC", "CHI"),
            ("134152", "DC United", "D.C. United", "DC"),
            ("134150", "Houston Dynamo", "Houston Dynamo FC", "HOU"),
            ("137699", "Inter Miami", "Inter Miami CF", "MIA"),
            ("136050", "Los Angeles FC", "LAFC", "LAFC"),
            ("135852", "Minnesota United", "Minnesota United FC", "MIN"),
            ("135853", "Orlando City", "Orlando City SC", "ORL"),
            ("134156", "New York Red Bulls", "Red Bull New York", "RBNY"),
            ("134157", "Seattle Sounders", "Seattle Sounders FC", "SEA"),
        ]
        // Same-city teams in other sports must not be claimed.
        let tsdb = pairs.map { Team(idTeam: $0.tsdbID, strTeam: $0.tsdb, strTeamShort: nil) }
            + [Team(idTeam: "134880", strTeam: "Atlanta Hawks", strTeamShort: "ATL"),
               Team(idTeam: "134152x", strTeam: "Seattle Kraken", strTeamShort: "SEA")]
        let espn: [Leagues: TeamResponse] = [
            .MLS: response(pairs.enumerated().map { i, p in
                espnTeam(id: "\(100 + i)", display: p.espn, name: p.espn, abbreviation: p.abbr, logo: "mls/\(p.abbr).png")
            }),
        ]
        let (teams, idMap) = ESPNTeamFetchJob().returnUpdatedTeams(teams: tsdb, espnTeamsByLeague: espn)
        let byID = Dictionary(uniqueKeysWithValues: teams.map { ($0.idTeam!, $0) })
        for p in pairs {
            XCTAssertEqual(byID[p.tsdbID]?.strTeamBadge, "mls/\(p.abbr).png", p.espn)
        }
        XCTAssertEqual(idMap.count, pairs.count)
        XCTAssertNil(byID["134880"]?.strTeamBadge)
        XCTAssertNil(byID["134152x"]?.strTeamBadge)
    }

    func test_clubKey() {
        XCTAssertEqual(ESPNTeamFetchJob.clubKey("Chicago Fire FC"), "chicago fire")
        XCTAssertEqual(ESPNTeamFetchJob.clubKey("D.C. United"), "dc united")
        XCTAssertEqual(ESPNTeamFetchJob.clubKey("Orlando City SC"), "orlando city")
        XCTAssertEqual(ESPNTeamFetchJob.clubKey("LAFC"), ESPNTeamFetchJob.clubKey("Los Angeles FC"))
        XCTAssertEqual(ESPNTeamFetchJob.clubKey("Arsenal"), "arsenal")
    }

    /// NFL: ESPN's 2-letter codes are the real ones and must reach the payload as-is.
    func test_nflTwoLetterCodesPassThrough() {
        let tsdb = [
            Team(idTeam: "134931", strTeam: "Kansas City Chiefs", strTeamShort: "KC"),
            Team(idTeam: "134948", strTeam: "San Francisco 49ers", strTeamShort: "SF"),
        ]
        let espn: [Leagues: TeamResponse] = [
            .nfl: response([
                espnTeam(id: "12", display: "Kansas City Chiefs", name: "Chiefs", abbreviation: "KC", logo: "nfl/kc.png"),
                espnTeam(id: "25", display: "San Francisco 49ers", name: "49ers", abbreviation: "SF", logo: "nfl/sf.png"),
            ]),
        ]
        let (teams, _) = ESPNTeamFetchJob().returnUpdatedTeams(teams: tsdb, espnTeamsByLeague: espn)
        let byID = Dictionary(uniqueKeysWithValues: teams.map { ($0.idTeam!, $0) })
        XCTAssertEqual(byID["134931"]?.strTeamShort, "KC")
        XCTAssertEqual(byID["134948"]?.strTeamShort, "SF")
    }
}
