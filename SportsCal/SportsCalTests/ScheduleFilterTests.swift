import XCTest
import SportsCalModel
@testable import Scoreline

/// Tests that GameViewModel filtering logic correctly shows/hides games
/// based on sport preferences and hidden competitions.
@MainActor
final class ScheduleFilterTests: XCTestCase {

    private var appStorage: UserDefaultStorage!
    private var favorites: Favorites!
    private var viewModel: GameViewModel!

    /// Keys to reset in tearDown to avoid test pollution
    private let sportKeys = [
        "shouldShowNBA", "shouldShowNFL", "shouldShowNHL",
        "shouldShowSoccer", "shouldShowMLB", "shouldShowGolf",
        "shouldShowTennis", "shouldShowRacing", "shouldShowCricket", "shouldShowCFB", "shouldShowWNBA", "shouldShowCBB", "shouldShowWorldCup", "cfbSelection", "hiddenCompetitions", "seededHiddenCompetitions",
        "favoritesOnlyNBA", "favoritesOnlyNFL", "favoritesOnlyNHL",
        "favoritesOnlySoccer", "favoritesOnlyMLB", "favoritesOnlyGolf",
        "favoritesOnlyTennis", "favoritesOnlyRacing",
        "coverageTennis", "coverageGolf",
        "Favorites", "FavoritePlayers"
    ]

    override func setUp() {
        super.setUp()
        // Clear stores before constructing UserDefaultStorage / Favorites so they
        // initialize from a clean state.
        let appGroup = UserDefaults(suiteName: "group.Komodo.SportsCal")
        for key in sportKeys {
            UserDefaults.standard.removeObject(forKey: key)
            appGroup?.removeObject(forKey: key)
        }

        appStorage = UserDefaultStorage()
        favorites = Favorites()
        viewModel = GameViewModel(appStorage: appStorage, favorites: favorites)

        // Build mock games with known counts per league
        let mockGames = buildMockGames()
        viewModel.totalGames = mockGames

        // Build gamesDict from totalGames (mirrors what setGames does)
        let validGames = mockGames.filter { game in
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let _ = Leagues(rawValue: intLeague) else { return false }
            return true
        }
        viewModel.gamesDict = Dictionary(grouping: validGames) { game in
            SportType(league: Leagues(rawValue: Int(game.idLeague!)!)!)
        }
    }

    override func tearDown() {
        let appGroup = UserDefaults(suiteName: "group.Komodo.SportsCal")
        for key in sportKeys {
            UserDefaults.standard.removeObject(forKey: key)
            appGroup?.removeObject(forKey: key)
        }
        super.tearDown()
    }

    // MARK: - Mock Data Builder

    /// Creates a small set of games across multiple sports with future timestamps
    private func buildMockGames() -> [Game] {
        let futureDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400))
        var games: [Game] = []

        // 5 NBA games
        for i in 0..<5 {
            games.append(Game(
                idEvent: "nba-\(i)", idLeague: "\(Leagues.nba.rawValue)",
                strHomeTeam: "Home NBA \(i)", strAwayTeam: "Away NBA \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }

        // 3 NFL games
        for i in 0..<3 {
            games.append(Game(
                idEvent: "nfl-\(i)", idLeague: "\(Leagues.nfl.rawValue)",
                strHomeTeam: "Home NFL \(i)", strAwayTeam: "Away NFL \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }

        // 4 NHL games
        for i in 0..<4 {
            games.append(Game(
                idEvent: "nhl-\(i)", idLeague: "\(Leagues.nhl.rawValue)",
                strHomeTeam: "Home NHL \(i)", strAwayTeam: "Away NHL \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }

        // 2 MLB games
        for i in 0..<2 {
            games.append(Game(
                idEvent: "mlb-\(i)", idLeague: "\(Leagues.mlb.rawValue)",
                strHomeTeam: "Home MLB \(i)", strAwayTeam: "Away MLB \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }

        // 6 Soccer: 3 EPL + 2 La Liga + 1 UCL
        for i in 0..<3 {
            games.append(Game(
                idEvent: "epl-\(i)", idLeague: "\(Leagues.English_Premier_League.rawValue)",
                strHomeTeam: "Home EPL \(i)", strAwayTeam: "Away EPL \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }
        for i in 0..<2 {
            games.append(Game(
                idEvent: "laliga-\(i)", idLeague: "\(Leagues.La_Liga.rawValue)",
                strHomeTeam: "Home LaLiga \(i)", strAwayTeam: "Away LaLiga \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }
        games.append(Game(
            idEvent: "ucl-0", idLeague: "\(Leagues.UEFA_Champions_League.rawValue)",
            strHomeTeam: "Home UCL", strAwayTeam: "Away UCL",
            strTimestamp: futureDate, isoDate: nil
        ))

        // 2 Golf (PGA)
        for i in 0..<2 {
            games.append(Game(
                idEvent: "pga-\(i)", idLeague: "\(Leagues.pga.rawValue)",
                strHomeTeam: "PGA Tournament \(i)", strAwayTeam: "Leader \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }

        // 2 Tennis (1 ATP + 1 WTA)
        games.append(Game(
            idEvent: "atp-0", idLeague: "\(Leagues.atp.rawValue)",
            strHomeTeam: "ATP Event", strAwayTeam: "ATP Leader",
            strTimestamp: futureDate, isoDate: nil
        ))
        games.append(Game(
            idEvent: "wta-0", idLeague: "\(Leagues.wta.rawValue)",
            strHomeTeam: "WTA Event", strAwayTeam: "WTA Leader",
            strTimestamp: futureDate, isoDate: nil
        ))

        // 1 Racing (F1)
        games.append(Game(
            idEvent: "f1-0", idLeague: "\(Leagues.formula1.rawValue)",
            strHomeTeam: "Grand Prix", strAwayTeam: "Leader",
            strTimestamp: futureDate, isoDate: nil
        ))

        return games
    }

    // MARK: - Tests

    func testFilterShowsOnlyEnabledSports() {
        appStorage.shouldShowNBA = true
        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(filtered.count, 5, "Only 5 NBA games should show")
        XCTAssertTrue(filtered.allSatisfy { $0.idLeague == "\(Leagues.nba.rawValue)" })
    }

    func testFilterShowsAllSportsWhenAllEnabled() {
        appStorage.shouldShowNBA = true
        appStorage.shouldShowNFL = true
        appStorage.shouldShowNHL = true
        appStorage.shouldShowMLB = true
        appStorage.shouldShowSoccer = true
        appStorage.shouldShowGolf = true
        appStorage.shouldShowTennis = true
        appStorage.shouldShowRacing = true
        // The mock golf and tennis events are tour-level; the default coverage (Big
        // Events) hides those, so ask for everything here.
        appStorage.coverageGolf = .everything
        appStorage.coverageTennis = .everything

        let filtered = viewModel.getGamesFromUserPreferences()
        // 5 NBA + 3 NFL + 4 NHL + 2 MLB + 6 Soccer + 2 Golf + 2 Tennis + 1 Racing = 25
        XCTAssertEqual(filtered.count, 25, "All 25 mock games should show when all sports enabled")
    }

    func testDefaultCoverageHidesTourLevelGolfAndTennis() {
        appStorage.shouldShowNBA = true
        appStorage.shouldShowNFL = true
        appStorage.shouldShowNHL = true
        appStorage.shouldShowMLB = true
        appStorage.shouldShowSoccer = true
        appStorage.shouldShowGolf = true
        appStorage.shouldShowTennis = true
        appStorage.shouldShowRacing = true

        let filtered = viewModel.getGamesFromUserPreferences()
        // Big Events is the default: "PGA Tournament 0" and "ATP Event" are tour-level.
        XCTAssertEqual(filtered.count, 21, "Team sports and racing show; tour-level golf and tennis don't")
        XCTAssertFalse(filtered.contains { $0.sportType == .golf || $0.sportType == .tennis })
    }

    func testFilterShowsNoSportsWhenAllDisabled() {
        // All sports disabled by default from setUp
        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(filtered.count, 0, "No games should show when all sports disabled")
    }

    func testSoccerFilterRespectsHiddenCompetitions() {
        appStorage.shouldShowSoccer = true

        // First verify all soccer shows
        let allSoccer = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(allSoccer.count, 6, "All 6 soccer games should show initially")

        // Hide La Liga
        appStorage.hiddenCompetitions = ["La Liga"]
        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(filtered.count, 4, "Should exclude 2 La Liga games, leaving 4")
        XCTAssertFalse(filtered.contains { $0.idLeague == "\(Leagues.La_Liga.rawValue)" })
    }

    func testFilteredGamesHaveValidLeagueIDs() {
        appStorage.shouldShowNBA = true
        appStorage.shouldShowSoccer = true
        appStorage.shouldShowGolf = true

        let filtered = viewModel.getGamesFromUserPreferences()
        let validLeagueIDs = Set(Leagues.allCases.map { "\($0.rawValue)" })

        for game in filtered {
            XCTAssertNotNil(game.idLeague, "Filtered game should have idLeague")
            XCTAssertTrue(
                validLeagueIDs.contains(game.idLeague ?? ""),
                "Game has invalid idLeague: \(game.idLeague ?? "nil")"
            )
        }
    }

    func testMultipleSportsFilter() {
        appStorage.shouldShowNBA = true
        appStorage.shouldShowNHL = true

        let filtered = viewModel.getGamesFromUserPreferences()
        // 5 NBA + 4 NHL = 9
        XCTAssertEqual(filtered.count, 9, "Should show 5 NBA + 4 NHL = 9 games")

        let sports = Set(filtered.compactMap { $0.strSport })
        XCTAssertEqual(sports, ["basketball", "hockey"])
    }

    // MARK: - Favorites-Only Tests

    func testFavoritesOnlyMLBShowsOnlyFavoritedTeamGames() {
        appStorage.shouldShowMLB = true
        appStorage.favoritesOnlyMLB = true
        favorites.add("Home MLB 0") // one of 2 mock MLB teams

        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(filtered.count, 1, "Only 1 MLB game should match the favorited team")
        XCTAssertEqual(filtered.first?.strHomeTeam, "Home MLB 0")
    }

    func testFavoritesOnlyMLBWithNoFavoritesReturnsEmpty() {
        appStorage.shouldShowMLB = true
        appStorage.favoritesOnlyMLB = true
        // No favorites added

        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(filtered.count, 0, "No games should show when favorites-only is on but no favorites exist")
    }

    func testFavoritesOnlyGolfMatchesOnFavoritedPlayer() {
        appStorage.shouldShowGolf = true
        appStorage.favoritesOnlyGolf = true
        favorites.addPlayer("Scottie Scheffler")

        // Inject a leaderboard containing the favorited player into the first golf game.
        guard var pga0 = viewModel.totalGames?.first(where: { $0.idEvent == "pga-0" }) else {
            return XCTFail("Mock PGA game missing")
        }
        pga0 = Game(
            idEvent: pga0.idEvent, idLeague: pga0.idLeague,
            strHomeTeam: pga0.strHomeTeam, strAwayTeam: pga0.strAwayTeam,
            strTimestamp: pga0.strTimestamp, isoDate: nil,
            leaderboardEntries: [
                LeaderboardEntry(name: "Scottie Scheffler", score: "-12", position: 1),
                LeaderboardEntry(name: "Rory McIlroy", score: "-10", position: 2)
            ]
        )
        var updated = viewModel.totalGames ?? []
        if let idx = updated.firstIndex(where: { $0.idEvent == "pga-0" }) { updated[idx] = pga0 }
        viewModel.totalGames = updated
        viewModel.gamesDict[.golf] = updated.filter { $0.idLeague == "\(Leagues.pga.rawValue)" }

        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(filtered.count, 1, "Only the tournament with Scheffler should remain")
        XCTAssertEqual(filtered.first?.idEvent, "pga-0")
    }

    func testSportToggleOffSuppressesFavoritesOnly() {
        appStorage.shouldShowMLB = false
        appStorage.favoritesOnlyMLB = true
        favorites.add("Home MLB 0")

        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertTrue(filtered.isEmpty, "Sport disabled should trump favorites-only")
    }

    func testHidingMultipleSoccerCompetitions() {
        appStorage.shouldShowSoccer = true
        appStorage.hiddenCompetitions = [
            Leagues.La_Liga.leagueName,
            Leagues.UEFA_Champions_League.leagueName
        ]

        let filtered = viewModel.getGamesFromUserPreferences()
        // Only EPL (3 games) should remain
        XCTAssertEqual(filtered.count, 3, "Should only show 3 EPL games after hiding La Liga + UCL")
        XCTAssertTrue(filtered.allSatisfy {
            $0.idLeague == "\(Leagues.English_Premier_League.rawValue)"
        })
    }

    // MARK: - College Football

    /// Adds three college games to the football bucket: a ranked matchup, an unranked
    /// SEC game, and an unranked Sun Belt game.
    private func addCollegeGames() -> [Game] {
        let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400))
        let league = "\(Leagues.ncaaf.rawValue)"
        let college = [
            Game(idEvent: "cfb-ranked", idLeague: league, strHomeTeam: "Missouri Tigers", strAwayTeam: "Florida Gators",
                 strTimestamp: future, isoDate: nil, homeSeed: 25, awaySeed: 8, homeConference: "sec", awayConference: "sec"),
            Game(idEvent: "cfb-sec", idLeague: league, strHomeTeam: "Kentucky Wildcats", strAwayTeam: "Arkansas Razorbacks",
                 strTimestamp: future, isoDate: nil, homeConference: "sec", awayConference: "sec"),
            Game(idEvent: "cfb-belt", idLeague: league, strHomeTeam: "Troy Trojans", strAwayTeam: "Texas State Bobcats",
                 strTimestamp: future, isoDate: nil, homeConference: "sunBelt", awayConference: "sunBelt"),
        ]
        viewModel.gamesDict[.nfl, default: []] += college
        return college
    }

    private func collegeIDs(_ games: [Game]) -> Set<String> {
        Set(games.filter(\.isCollegeFootball).compactMap(\.idEvent))
    }

    func testNFLOnlyHidesCollege() {
        _ = addCollegeGames()
        appStorage.shouldShowNFL = true
        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertTrue(collegeIDs(filtered).isEmpty)
        XCTAssertFalse(filtered.isEmpty, "NFL games still show")
    }

    func testCollegeOnlyHidesNFLAndDefaultsToTop25() {
        _ = addCollegeGames()
        appStorage.shouldShowCFB = true
        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertTrue(filtered.allSatisfy(\.isCollegeFootball))
        XCTAssertEqual(collegeIDs(filtered), ["cfb-ranked"])
    }

    func testCollegeSelectionCombinesPicks() {
        _ = addCollegeGames()
        appStorage.shouldShowCFB = true
        appStorage.cfbSelection = CollegeFootballSelection(conferences: [.sunBelt])
        XCTAssertEqual(collegeIDs(viewModel.getGamesFromUserPreferences()), ["cfb-belt"])
        appStorage.cfbSelection = CollegeFootballSelection(top25: true, conferences: [.sunBelt])
        XCTAssertEqual(collegeIDs(viewModel.getGamesFromUserPreferences()), ["cfb-ranked", "cfb-belt"])
        appStorage.cfbSelection = .powerFour
        XCTAssertEqual(collegeIDs(viewModel.getGamesFromUserPreferences()), ["cfb-ranked", "cfb-sec"])
        appStorage.cfbSelection = .allFBS
        XCTAssertEqual(collegeIDs(viewModel.getGamesFromUserPreferences()), ["cfb-ranked", "cfb-sec", "cfb-belt"])
        appStorage.cfbSelection = .followedOnly
        XCTAssertTrue(collegeIDs(viewModel.getGamesFromUserPreferences()).isEmpty)
    }

    func testFollowedCollegeTeamShowsUnderAnySelection() {
        _ = addCollegeGames()
        appStorage.shouldShowCFB = true
        appStorage.cfbSelection = .followedOnly
        favorites.add("Troy Trojans")
        XCTAssertEqual(collegeIDs(viewModel.getGamesFromUserPreferences()), ["cfb-belt"])
    }

    func testCollegeFootballFollowSkipsTheSchoolsBasketballTeam() {
        // Both Missouri teams are "Missouri Tigers"; only their IDs tell them apart.
        let football = Game(idEvent: "cfb", idLeague: "\(Leagues.ncaaf.rawValue)", idHomeTeam: "ncaaf-142", idAwayTeam: "ncaaf-57",
                            strHomeTeam: "Missouri Tigers", strAwayTeam: "Florida Gators", isoDate: nil)
        let hoops = Game(idEvent: "cbb", idLeague: "\(Leagues.ncaaMBBTournament.rawValue)", idHomeTeam: "142", idAwayTeam: "57",
                         strHomeTeam: "Missouri Tigers", strAwayTeam: "Florida Gators", isoDate: nil)
        favorites.add(football, home: true)
        XCTAssertTrue(favorites.contains(football))
        XCTAssertFalse(favorites.contains(hoops))
        XCTAssertTrue(favorites.teams.contains("Missouri Tigers"))
        XCTAssertEqual(favorites.pushToStartKeys, ["ncaaf-142"], "push-to-start gets the ID, not the shared name")

        favorites.remove(football, home: true)
        favorites.add(hoops, home: true)
        XCTAssertTrue(favorites.contains(hoops))
        XCTAssertFalse(favorites.contains(football))
        XCTAssertEqual(favorites.pushToStartKeys, ["Missouri Tigers"])
    }

    func testFootballSectionsFollowThePicks() {
        let college = addCollegeGames()
        appStorage.shouldShowNFL = true
        appStorage.shouldShowCFB = true
        appStorage.cfbSelection = CollegeFootballSelection(top25: true, conferences: [.sec, .sunBelt])
        let nfl = viewModel.gamesDict[.nfl]?.filter { !$0.isCollegeFootball } ?? []
        let sections = appStorage.footballPreference.sections(nfl + college) { _ in false }
        XCTAssertEqual(sections.map(\.section), [.nfl, .top25, .conference(.sec), .conference(.sunBelt)])
        XCTAssertEqual(sections[1].games.compactMap(\.idEvent), ["cfb-ranked"], "a ranked SEC game appears once, under Top 25")
    }

    func testFootballCountsAsOnForCollegeOnlyFans() {
        appStorage.shouldShowCFB = true
        XCTAssertTrue(appStorage.userShouldShow(.nfl))
        appStorage.toggleSport(.nfl, enabled: false)
        XCTAssertFalse(appStorage.shouldShowCFB, "Turning football off turns college off too")
    }

    // MARK: - Following a team's competitions

    func testFollowingCompetitionsTurnsOnTheSportAndUnhidesCups() {
        appStorage.shouldShowSoccer = false
        appStorage.hiddenCompetitions = [Leagues.FA_Cup.leagueName, Leagues.La_Liga.leagueName]

        let changed = appStorage.followCompetitions([.English_Premier_League, .UEFA_Champions_League, .FA_Cup])

        XCTAssertTrue(changed)
        XCTAssertTrue(appStorage.shouldShowSoccer)
        XCTAssertFalse(appStorage.hiddenCompetitions.contains(Leagues.FA_Cup.leagueName))
        XCTAssertTrue(appStorage.hiddenCompetitions.contains(Leagues.La_Liga.leagueName),
                      "Competitions the team doesn't play in stay hidden")
        XCTAssertTrue(appStorage.enabledSports.contains(.soccer))
    }

    func testFollowingCompetitionsUsesEachLeaguesOwnToggle() {
        appStorage.shouldShowCricket = false
        appStorage.shouldShowCFB = false
        appStorage.followCompetitions([.ipl, .ncaaf])
        XCTAssertTrue(appStorage.shouldShowCricket)
        XCTAssertTrue(appStorage.shouldShowCFB)
    }

    func testFollowingAlreadyVisibleCompetitionsChangesNothing() {
        appStorage.shouldShowNBA = true
        appStorage.hiddenCompetitions = []
        XCTAssertFalse(appStorage.followCompetitions([.nba]))
    }

    // MARK: - Onboarding league map

    func testOnboardingSelectionTurnsOnPickedSportsAndHidesTheRest() {
        appStorage.shouldShowNBA = true
        appStorage.shouldShowCricket = true
        appStorage.applyOnboardingSelection([.English_Premier_League, .UEFA_Champions_League, .FA_Cup, .nfl])

        XCTAssertTrue(appStorage.shouldShowSoccer)
        XCTAssertTrue(appStorage.shouldShowNFL)
        XCTAssertFalse(appStorage.shouldShowNBA, "Nothing in basketball was picked")
        XCTAssertFalse(appStorage.shouldShowCricket)
        XCTAssertFalse(appStorage.shouldShowCFB)
        XCTAssertFalse(appStorage.shouldShowWorldCup)
        for league in [Leagues.English_Premier_League, .UEFA_Champions_League, .FA_Cup] {
            XCTAssertFalse(appStorage.hiddenCompetitions.contains(league.leagueName), "\(league) was picked")
        }
        for league in [Leagues.La_Liga, .Serie_A, .English_League_Championship, .FIFA_World_Cup] {
            XCTAssertTrue(appStorage.hiddenCompetitions.contains(league.leagueName), "\(league) wasn't picked")
        }
        XCTAssertEqual(Set(appStorage.enabledSports), [.soccer, .nfl])

        viewModel.filterSports(force: true)
        let leagues = Set(viewModel.getGamesFromUserPreferences().compactMap(\.idLeague))
        XCTAssertFalse(leagues.contains(String(Leagues.nba.rawValue)))
        XCTAssertFalse(leagues.contains(String(Leagues.La_Liga.rawValue)))
    }

    func testOnboardingSelectionLeavesUnpickedSportsCompetitionsAlone() {
        appStorage.hiddenCompetitions = [Leagues.wbbl.leagueName]
        appStorage.applyOnboardingSelection([.nba])
        XCTAssertEqual(appStorage.hiddenCompetitions, [Leagues.wbbl.leagueName],
                       "Cricket wasn't picked, so its competitions keep their own settings")
        XCTAssertFalse(appStorage.shouldShowCricket)
    }

    func testWorldCupOnlyUsesItsOwnSwitch() {
        appStorage.hiddenCompetitions = [Leagues.FIFA_World_Cup.leagueName]
        appStorage.applyOnboardingSelection([.FIFA_World_Cup])
        XCTAssertTrue(appStorage.shouldShowWorldCup)
        XCTAssertFalse(appStorage.shouldShowSoccer)
        XCTAssertFalse(appStorage.hiddenCompetitions.contains(Leagues.FIFA_World_Cup.leagueName))
        XCTAssertFalse(appStorage.hiddenCompetitions.contains(Leagues.La_Liga.leagueName),
                       "Soccer is off, so nothing else in it needs hiding")
    }

    func testOnboardingSelectionHidesUnpickedSeriesAndTours() {
        appStorage.applyOnboardingSelection([.formula1, .atp, .pga, .ipl])
        XCTAssertTrue(appStorage.shouldShowRacing)
        XCTAssertTrue(appStorage.shouldShowTennis)
        XCTAssertTrue(appStorage.shouldShowGolf)
        XCTAssertTrue(appStorage.shouldShowCricket)
        let hidden = Set(appStorage.hiddenCompetitions)
        XCTAssertFalse(hidden.contains(Leagues.formula1.leagueName))
        XCTAssertTrue(hidden.contains(Leagues.nascarCup.leagueName))
        XCTAssertTrue(hidden.contains(Leagues.wta.leagueName))
        XCTAssertTrue(hidden.contains(Leagues.livGolf.leagueName))
        XCTAssertTrue(hidden.contains(Leagues.cricketTests.leagueName))
        XCTAssertFalse(hidden.contains(Leagues.ipl.leagueName))
        XCTAssertEqual(appStorage.visibleMotorsportSeries, [])
    }

    func testOnboardingSelectionUnhidesPickedDefaultHiddenLeagues() {
        XCTAssertTrue(appStorage.hiddenCompetitions.contains(Leagues.A_League.leagueName), "Seeded hidden")
        appStorage.applyOnboardingSelection([.A_League, .nascarCup])
        XCTAssertFalse(appStorage.hiddenCompetitions.contains(Leagues.A_League.leagueName))
        XCTAssertEqual(appStorage.visibleMotorsportSeries, [Leagues.nascarCup.leagueName])
    }

    func testEveryLeagueIsSomewhereOnTheMap() {
        let mapped = Set(LeagueMap.allHubs.flatMap(\.leagues).map(\.league))
        XCTAssertEqual(mapped, Set(Leagues.allCases), "Unpicked competitions get hidden, so each must be pickable")
        for pack in LeagueMap.packs {
            for item in pack.items {
                XCTAssertTrue(LeagueMap.hub(id: item.hub)?.leagues.contains { $0.league == item.league } ?? false,
                              "\(pack.name): \(item.league) isn't in \(item.hub)")
            }
        }
    }

    func testRegionDefaultsAreOnTheMap() {
        XCTAssertEqual(LeagueMap.regionDefaults(forRegion: "us"), [.nfl, .nba])
        XCTAssertEqual(LeagueMap.regionDefaults(forRegion: "GB"), [.English_Premier_League])
        XCTAssertEqual(LeagueMap.regionDefaults(forRegion: nil), [.English_Premier_League, .UEFA_Champions_League])
        XCTAssertEqual(LeagueMap.regionHubID(forRegion: "NZ"), "AU")
        XCTAssertNil(LeagueMap.regionHubID(forRegion: "JP"))
        for region in ["US", "CA", "MX", "GB", "DE", "IN", "PK", "LK", "AU", "NZ", "ZA", "AE", "JM", "BR", "JP"] {
            let hub = LeagueMap.regionHubID(forRegion: region).flatMap(LeagueMap.hub(id:))
            XCTAssertFalse(LeagueMap.regionDefaults(forRegion: region).isEmpty)
            if let hub {
                XCTAssertTrue(hub.leagues.contains { LeagueMap.regionDefaults(forRegion: region).contains($0.league) }
                              || region == "BR" || region == "LK",
                              "\(region)'s spot should light up with its picks")
            }
        }
    }

    func testEuropeClusterNeedsZoomingOnAPhone() {
        let europe = LeagueMap.clusters.first { $0.id == "europe" }!
        // An iPhone fits the 360-unit map at ~1.08pt per unit: far too tight for 44pt targets.
        XCTAssertLessThan(europe.minimumSpacing * 1.08, 44)
        XCTAssertGreaterThanOrEqual(europe.minimumSpacing * europe.scale(forSpacing: 50), 49.9)
    }

    func testMapSelectionTray() {
        var selection = LeagueMapSelection()
        XCTAssertEqual(selection.continueTitle, "Pick a League to Continue")
        selection.add(team: Team(idTeam: "133604", strTeam: "Arsenal"),
                      competitions: [.English_Premier_League, .UEFA_Champions_League, .FA_Cup])
        selection.add(.English_Premier_League)
        XCTAssertEqual(selection.continueTitle, "Continue · 1 team, 3 leagues")
        selection.remove(team: Team(idTeam: "133604", strTeam: "Arsenal"))
        XCTAssertEqual(selection.continueTitle, "Continue · 3 leagues")
        XCTAssertEqual(LeagueMap.hubIDs(containing: .MLS), ["US", "CA"])
        XCTAssertEqual(LeagueMap.hub(id: "GB")?.accessibilityLabel(followed: 2), "England, 6 leagues, 2 followed")
    }

    func testScheduleTeamLeaguesPutTheLeagueBeforeCups() {
        let date = ISO8601DateFormatter().string(from: Date())
        let cup = Game(idEvent: "c", idLeague: "\(Leagues.FA_Cup.rawValue)", idHomeTeam: "1",
                       strHomeTeam: "Arsenal", strAwayTeam: "Leeds", strTimestamp: date, isoDate: nil)
        let league = Game(idEvent: "l", idLeague: "\(Leagues.English_Premier_League.rawValue)", idHomeTeam: "1",
                          strHomeTeam: "Arsenal", strAwayTeam: "Spurs", strTimestamp: date, isoDate: nil)
        XCTAssertEqual(LeagueMap.teamLeagues(from: [cup, league, league])["1"], [.English_Premier_League, .FA_Cup])
    }
}
