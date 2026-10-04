//
//  CollegeFootballTests.swift
//  SportsCalModelTests
//

import XCTest
@testable import SportsCalModel

final class CollegeFootballTests: XCTestCase {

    /// Trimmed from ESPN's FBS board (`groups=80&dates=2026`): three unranked regular-season
    /// games (American, Big 12 vs CUSA, Big 12), two CFP quarterfinals, and #8 Florida at
    /// #25 Missouri.
    private func fixtureGames() throws -> [Game] {
        let board = try XCTUnwrap(JSONLoader.load(file: "CollegeFootballScoreboard", type: Scoreboard.self) as? Scoreboard)
        return try XCTUnwrap(LiveEvent(events: board, league: .ncaaf)).events
    }

    private func game(_ id: String, in games: [Game]) throws -> Game {
        try XCTUnwrap(games.first { $0.idEvent == id })
    }

    // MARK: - Parsing

    func testESPNBoardParsesAsCollegeFootballInTheFootballSport() throws {
        let games = try fixtureGames()
        XCTAssertEqual(games.count, 6)
        for game in games {
            XCTAssertEqual(game.idLeague, "102")
            XCTAssertTrue(game.isCollegeFootball)
            XCTAssertEqual(game.sportType, .nfl)
            // Namespaced so they can't collide with the WNBA's raw ESPN IDs.
            XCTAssertTrue(game.idHomeTeam?.hasPrefix("ncaaf-") == true, game.idHomeTeam ?? "nil")
        }
    }

    func testCollegeTeamIDRoundTrip() {
        XCTAssertEqual(Leagues.ncaaf.teamID(espnID: "57"), "ncaaf-57")
        XCTAssertEqual(Leagues.wnba.teamID(espnID: "5"), "5")
        XCTAssertEqual(Leagues.collegeESPNTeamID("ncaaf-57"), "57")
        XCTAssertNil(Leagues.collegeESPNTeamID("5"))
    }

    func testAPRanksBecomeSeedsAndUnrankedIsDropped() throws {
        let games = try fixtureGames()
        let florida = try game("401856708", in: games)
        XCTAssertEqual(florida.awaySeed, 8)
        XCTAssertEqual(florida.homeSeed, 25)
        // ESPN's 99 = unranked.
        let memphis = try game("401862787", in: games)
        XCTAssertNil(memphis.homeSeed)
        XCTAssertNil(memphis.awaySeed)
    }

    func testConferencesMapToShortNamesAndSurviveARoundTrip() throws {
        let games = try fixtureGames()
        let kansas = try game("401856807", in: games)
        XCTAssertEqual(kansas.collegeConferences, [.big12, .cusa])

        let decoded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(kansas))
        XCTAssertEqual(decoded.collegeConferences, [.big12, .cusa])
    }

    func testUnknownConferenceIsFCS() {
        XCTAssertEqual(CollegeConference(espnID: "8"), .sec)
        XCTAssertEqual(CollegeConference(espnID: "29"), .fcs)
        XCTAssertNil(CollegeConference(espnID: ""))
    }

    func testPostseasonCarriesTheBowlAndSeason() throws {
        let games = try fixtureGames()
        let rose = try game("401769072", in: games)
        XCTAssertEqual(rose.seasonPhase, .postseason)
        XCTAssertEqual(rose.season, "2025")
        XCTAssertTrue(rose.isCollegeFootballPlayoff)
        XCTAssertTrue(rose.playoff?.seriesTitle?.contains("Rose Bowl") == true)

        let regular = try game("401856708", in: games)
        XCTAssertEqual(regular.season, "2026")
        XCTAssertFalse(regular.isCollegeFootballPlayoff)
    }

    func testSeasonLabelRollsJanuaryBackToTheSeasonItEnds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let january = calendar.date(from: DateComponents(year: 2027, month: 1, day: 12))!
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!
        XCTAssertEqual(Leagues.ncaaf.seasonLabel(for: january, calendar: calendar), "2026")
        XCTAssertEqual(Leagues.ncaaf.seasonLabel(for: october, calendar: calendar), "2026")
    }

    // MARK: - Wire format

    /// What an app version from before college football decodes: the same keys, minus `ncaaf`.
    private struct LegacyLiveScore: Decodable {
        var nfl: LiveEvent?
    }

    private func mixedScore() throws -> LiveScore {
        let nflGame = Game(idEvent: "nfl-1", idLeague: "4391", strHomeTeam: "Kansas City Chiefs", strAwayTeam: "Buffalo Bills", isoDate: nil)
        return LiveScore(nfl: LiveEvent(events: [nflGame] + (try fixtureGames())))
    }

    func testOlderClientsNeverSeeCollegeGames() throws {
        let data = try JSONEncoder().encode(try mixedScore())
        let legacy = try JSONDecoder().decode(LegacyLiveScore.self, from: data)
        XCTAssertEqual(legacy.nfl?.events.map(\.idEvent), ["nfl-1"])
    }

    func testCurrentClientsFoldCollegeBackIntoFootball() throws {
        let score = try mixedScore()
        let decoded = try JSONDecoder().decode(LiveScore.self, from: JSONEncoder().encode(score))
        XCTAssertEqual(decoded.nfl?.events.count, 7)
        XCTAssertEqual(Set(decoded.nfl?.events.compactMap(\.idEvent) ?? []), Set(score.nfl?.events.compactMap(\.idEvent) ?? []))
    }

    func testCollegeOnlyBucketStillSendsAnEmptyNFLKey() throws {
        let score = LiveScore(nfl: LiveEvent(events: try fixtureGames()))
        let data = try JSONEncoder().encode(score)
        let legacy = try JSONDecoder().decode(LegacyLiveScore.self, from: data)
        XCTAssertNotNil(legacy.nfl)
        XCTAssertEqual(legacy.nfl?.events.count, 0)
    }

    func testDeltaOfOnlyCollegeGamesMergesForCurrentClients() throws {
        let base = try mixedScore()
        let changed = try fixtureGames()[0]
        let wireDelta = try JSONDecoder().decode(LiveScore.self, from: JSONEncoder().encode(LiveScore(nfl: LiveEvent(events: [changed]))))
        let merged = base.applying(delta: wireDelta, removed: ["nfl-1"])
        XCTAssertEqual(merged.nfl?.events.count, 6)
        XCTAssertFalse(merged.nfl?.events.contains { $0.idEvent == "nfl-1" } ?? true)
    }

    // MARK: - Selection

    private func admitted(_ selection: CollegeFootballSelection, _ games: [Game]) -> Set<String> {
        Set(games.filter { selection.admits($0) }.compactMap(\.idEvent))
    }

    func testSelectionsCombineTop25AndConferences() throws {
        let games = try fixtureGames()
        XCTAssertEqual(admitted(.followedOnly, games), [])
        // Florida/Missouri (ranked) and the two CFP quarterfinals.
        XCTAssertEqual(admitted(.default, games), ["401856708", "401769072", "401769073"])
        // Big 12 alone: Kansas and Iowa State, nothing ranked.
        XCTAssertEqual(admitted(CollegeFootballSelection(conferences: [.big12]), games), ["401856807", "401856822"])
        // Top 25 + Big 12.
        XCTAssertEqual(admitted(CollegeFootballSelection(top25: true, conferences: [.big12]), games),
                       ["401856708", "401769072", "401769073", "401856807", "401856822"])
        XCTAssertEqual(admitted(.allFBS, games).count, 6)
    }

    func testFollowedTeamsPassEverySelection() throws {
        let memphis = try game("401862787", in: try fixtureGames())
        for selection in [CollegeFootballSelection.followedOnly, .default, .powerFour] {
            XCTAssertFalse(selection.admits(memphis))
            XCTAssertTrue(selection.admits(memphis, isFavorite: true))
        }
    }

    func testSelectionNeverHidesTheNFL() {
        let nflGame = Game(idEvent: "nfl-1", idLeague: "4391", strHomeTeam: "Kansas City Chiefs", strAwayTeam: "Buffalo Bills", isoDate: nil)
        XCTAssertTrue(CollegeFootballSelection.followedOnly.admits(nflGame))
    }

    func testSelectionRawValueRoundTripsInStableOrder() {
        let selection = CollegeFootballSelection(top25: true, conferences: [.big12, .sec])
        XCTAssertEqual(selection.rawValue, "top25,sec,big12")
        XCTAssertEqual(CollegeFootballSelection(rawValue: selection.rawValue), selection)
        XCTAssertEqual(CollegeFootballSelection(rawValue: "")?.isFollowedOnly, true)
        // An unknown conference from a newer build is ignored, not fatal.
        XCTAssertEqual(CollegeFootballSelection(rawValue: "top25,newConf"), .default)
    }

    func testSummaries() {
        XCTAssertEqual(CollegeFootballSelection.default.summary, "Top 25")
        XCTAssertEqual(CollegeFootballSelection.powerFour.summary, "Top 25, Power 4")
        XCTAssertEqual(CollegeFootballSelection.allFBS.summary, "All FBS")
        XCTAssertEqual(CollegeFootballSelection.followedOnly.summary, "Teams I Follow")
        XCTAssertEqual(CollegeFootballSelection(conferences: [.big12, .sec]).summary, "SEC, Big 12")
    }

    func testStoredSelectionFallsBackToTop25() {
        let defaults = UserDefaults(suiteName: "CollegeFootballTests")!
        defaults.removePersistentDomain(forName: "CollegeFootballTests")
        XCTAssertEqual(CollegeFootballSelection.stored(in: defaults), .default)
        defaults.set("big12", forKey: CollegeFootballSelection.storageKey)
        XCTAssertEqual(CollegeFootballSelection.stored(in: defaults), CollegeFootballSelection(conferences: [.big12]))
    }

    // MARK: - Sections

    func testEachGameLandsInItsFirstMatchingSection() throws {
        let games = try fixtureGames()
        let football = FootballPreference(showNFL: true, showCollege: true,
                                          college: CollegeFootballSelection(top25: true, conferences: [.big12, .sec]))
        let nflGame = Game(idEvent: "nfl-1", idLeague: "4391", strHomeTeam: "Kansas City Chiefs", strAwayTeam: "Buffalo Bills", isoDate: nil)
        let sections = football.sections([nflGame] + games) { _ in false }
        XCTAssertEqual(sections.map(\.section), [.nfl, .playoff, .top25, .conference(.big12)])
        XCTAssertEqual(sections.map { $0.games.compactMap(\.idEvent) }, [
            ["nfl-1"],
            ["401769072", "401769073"],
            // Florida at Missouri is an SEC game, but ranked: it reads as Top 25, once.
            ["401856708"],
            ["401856807", "401856822"],
        ])
    }

    func testFollowedGameOutsideThePicksGetsACatchAllSection() throws {
        let games = try fixtureGames()
        let football = FootballPreference(showNFL: false, showCollege: true, college: .followedOnly)
        let sections = football.sections(games) { $0.idEvent == "401862787" }
        XCTAssertEqual(sections.map(\.section), [.college])
        XCTAssertEqual(sections.first?.games.compactMap(\.idEvent), ["401862787"])
    }

    func testFeaturedGamesAreTheBudgetedOnes() throws {
        let games = try fixtureGames()
        let featured = Set(games.filter(\.isFeaturedCollegeGame).compactMap(\.idEvent))
        // Ranked or Playoff, plus Power Four (Kansas, Iowa State); Memphis–Charlotte is not.
        XCTAssertEqual(featured, ["401856708", "401769072", "401769073", "401856807", "401856822"])
    }
}
