//
//  SportsCalTests.swift
//  SportsCalTests
//
//  Created by Umar Haroon on 3/24/23.
//

import XCTest
import SportsCalModel
@testable import Scoreline
final class SportsCalTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // MARK: - Helpers

    private func games(in events: [Game], forLeague league: Leagues) -> [Game] {
        events.filter { $0.idLeague == "\(league.rawValue)" }
    }

    func testStableLeagueGameCounts() async throws {
        let result: LiveScore
        do {
            // Tests bypass .auto and force .dev so CI hits the staging server.
            NetworkHandler.currentEnvironment = .dev
            NetworkHandler.resolvedEnvironment = .dev
            result = try await NetworkHandler.handleCall()
        } catch {
            throw XCTSkip("Network unavailable: \(error.localizedDescription)")
        }

        let allSportEvents: [(LiveEvent?, String)] = [
            (result.nba, "NBA"), (result.nfl, "NFL"), (result.nhl, "NHL"),
            (result.mlb, "MLB"), (result.soccer, "Soccer"),
            (result.golf, "Golf"), (result.tennis, "Tennis"), (result.racing, "Racing")
        ]

        // Collect all valid games
        let allEvents = allSportEvents.compactMap { $0.0 }.flatMap { $0.events }
        let validGames = allEvents.filter { game in
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let _ = Leagues(rawValue: intLeague) else { return false }
            return true
        }

        let month = Calendar.current.component(.month, from: Date())

        // API returns multi-season data (current + previous season)

        // NBA (Oct–Jun): 2 seasons regular + playoffs
        if (10...12).contains(month) || (1...6).contains(month) {
            let nba = games(in: validGames, forLeague: .nba)
            XCTAssertGreaterThanOrEqual(nba.count, 2400, "NBA should have ≥2400 games (2 seasons), got \(nba.count)")
            XCTAssertLessThanOrEqual(nba.count, 2800, "NBA should have ≤2800 games, got \(nba.count)")
        }

        // NHL (Oct–Jun): 2 seasons regular + playoffs
        if (10...12).contains(month) || (1...6).contains(month) {
            let nhl = games(in: validGames, forLeague: .nhl)
            XCTAssertGreaterThanOrEqual(nhl.count, 2600, "NHL should have ≥2600 games (2 seasons), got \(nhl.count)")
            XCTAssertLessThanOrEqual(nhl.count, 3100, "NHL should have ≤3100 games, got \(nhl.count)")
        }

        // MLB (Apr–Oct): early season has fewer games, full season ramps up
        if (4...10).contains(month) {
            let mlb = games(in: validGames, forLeague: .mlb)
            // Early April may have very few games as the season just started
            if month >= 5 {
                XCTAssertGreaterThanOrEqual(mlb.count, 2400, "MLB should have ≥2400 games after April, got \(mlb.count)")
            } else {
                XCTAssertGreaterThan(mlb.count, 0, "MLB should have some games in April, got \(mlb.count)")
            }
        }

        // NFL (Sep–Feb): multi-season
        if (9...12).contains(month) || (1...2).contains(month) {
            let nfl = games(in: validGames, forLeague: .nfl)
            XCTAssertGreaterThanOrEqual(nfl.count, 272, "NFL should have ≥272 games, got \(nfl.count)")
        }

        // Soccer domestic leagues (Aug–May): 2 seasons
        if (8...12).contains(month) || (1...5).contains(month) {
            let epl = games(in: validGames, forLeague: .English_Premier_League)
            XCTAssertGreaterThanOrEqual(epl.count, 760, "EPL should have ≥760 games (2×380), got \(epl.count)")

            let laLiga = games(in: validGames, forLeague: .La_Liga)
            XCTAssertGreaterThanOrEqual(laLiga.count, 760, "La Liga should have ≥760 games (2×380), got \(laLiga.count)")

            let serieA = games(in: validGames, forLeague: .Serie_A)
            XCTAssertGreaterThanOrEqual(serieA.count, 760, "Serie A should have ≥760 games (2×380), got \(serieA.count)")

            let bundesliga = games(in: validGames, forLeague: .German_Bundesliga)
            XCTAssertGreaterThanOrEqual(bundesliga.count, 612, "Bundesliga should have ≥612 games (2×306), got \(bundesliga.count)")

            let ligue1 = games(in: validGames, forLeague: .Ligue_1)
            XCTAssertGreaterThanOrEqual(ligue1.count, 612, "Ligue 1 should have ≥612 games (2×306), got \(ligue1.count)")

            let eredivisie = games(in: validGames, forLeague: .Eredivisie)
            XCTAssertGreaterThanOrEqual(eredivisie.count, 612, "Eredivisie should have ≥612 games (2×306), got \(eredivisie.count)")
        }

        // F1: 2 seasons
        if let racingEvents = result.racing?.events {
            let f1 = games(in: racingEvents, forLeague: .formula1)
            XCTAssertGreaterThanOrEqual(f1.count, 22, "F1 should have ≥22 events, got \(f1.count)")
            XCTAssertLessThanOrEqual(f1.count, 50, "F1 should have ≤50 events, got \(f1.count)")
        }

        // PGA: multi-season tournaments
        if let golfEvents = result.golf?.events {
            let pga = games(in: golfEvents, forLeague: .pga)
            XCTAssertGreaterThanOrEqual(pga.count, 80, "PGA should have ≥80 events, got \(pga.count)")
            XCTAssertLessThanOrEqual(pga.count, 400, "PGA should have ≤400 events (two seasons), got \(pga.count)")
        }

        // Tennis: individual matches (counts vary by time of year)
        if let tennisEvents = result.tennis?.events {
            let atp = games(in: tennisEvents, forLeague: .atp)
            XCTAssertGreaterThanOrEqual(atp.count, 5000, "ATP should have ≥5000 matches, got \(atp.count)")

            let wta = games(in: tennisEvents, forLeague: .wta)
            XCTAssertGreaterThanOrEqual(wta.count, 5000, "WTA should have ≥5000 matches, got \(wta.count)")
        }
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            let model = GameViewModel(appStorage: .init(), favorites: .init())
            model.sortedGames.count
            // Put the code you want to measure the time of here.
        }
    }

}

// MARK: - Live → schedule merge

@MainActor
enum CoreFixTestSupport {
    /// Every sport on, so fixture games survive the preference filter.
    static func storage() -> UserDefaultStorage {
        let storage = UserDefaultStorage()
        storage.shouldShowNBA = true
        storage.shouldShowNFL = true
        storage.shouldShowNHL = true
        storage.shouldShowSoccer = true
        storage.shouldShowMLB = true
        storage.shouldShowGolf = true
        storage.shouldShowTennis = true
        storage.shouldShowRacing = true
        return storage
    }
}

/// Pins `GameViewModel.mergeLiveIntoSchedule` / `patchDerivedCollections` against the
/// regressions their comments describe: same-matchup games on different days colliding,
/// a merge renaming a synthesized id, and the live overlay carrying scores into every
/// derived collection.
@MainActor
final class LiveScheduleMergeTests: XCTestCase {

    override func setUp() async throws {
        GameViewModel.isSnapshotTesting = true
    }

    private let nhl = "\(Leagues.nhl.rawValue)"

    private func iso(_ offset: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset))
    }

    private func viewModel(with games: [Game]) -> GameViewModel {
        let vm = GameViewModel(appStorage: CoreFixTestSupport.storage(), favorites: Favorites())
        vm.applySnapshotFixtures(games: games)
        return vm
    }

    private func liveScore(nhl games: [Game]) -> LiveScore {
        LiveScore(nhl: LiveEvent(events: games))
    }

    func testEventIDMatchDoesNotLeakIntoSameMatchupOnAnotherDay() throws {
        let today = Game(idEvent: "today", idLeague: nhl, strHomeTeam: "Avalanche", strAwayTeam: "Wild",
                         strTimestamp: iso(-3600), isoDate: nil)
        let tuesday = Game(idEvent: "tuesday", idLeague: nhl, strHomeTeam: "Avalanche", strAwayTeam: "Wild",
                           strTimestamp: iso(2 * 86400), isoDate: nil)
        let vm = viewModel(with: [today, tuesday])

        let live = Game(idEvent: "today", idLeague: nhl, strHomeTeam: "Avalanche", strAwayTeam: "Wild",
                        intHomeScore: "4", intAwayScore: "1", strStatus: "post",
                        strTimestamp: iso(-3600), isCompleted: true, isoDate: nil)
        vm.mergeLiveIntoSchedule(liveScore(nhl: [live]))

        let merged = try XCTUnwrap(vm.totalGames?.first { $0.idEvent == "today" })
        XCTAssertEqual(merged.intHomeScore, "4")
        XCTAssertEqual(merged.intAwayScore, "1")
        let untouched = try XCTUnwrap(vm.totalGames?.first { $0.idEvent == "tuesday" })
        XCTAssertNil(untouched.intHomeScore, "Tuesday's fixture must not pick up today's score")
        XCTAssertNotEqual(untouched.strStatus, "post")
    }

    func testScheduledGameWithEventIDNeverFallsBackToTeamNames() throws {
        let scheduled = Game(idEvent: "tuesday", idLeague: nhl, strHomeTeam: "Avalanche", strAwayTeam: "Wild",
                             strTimestamp: iso(2 * 86400), isoDate: nil)
        let vm = viewModel(with: [scheduled])

        // Same matchup, different id: a team-name fallback would wrongly match it.
        let live = Game(idEvent: "other", idLeague: nhl, strHomeTeam: "Avalanche", strAwayTeam: "Wild",
                        intHomeScore: "2", intAwayScore: "2", strStatus: "in",
                        strTimestamp: iso(-600), isoDate: nil)
        vm.mergeLiveIntoSchedule(liveScore(nhl: [live]))

        XCTAssertNil(vm.totalGames?.first?.intHomeScore)
    }

    func testTeamNameFallbackRequiresSameCalendarDay() {
        let tomorrow = Game(idEvent: nil, idLeague: nhl, strHomeTeam: "Avalanche", strAwayTeam: "Wild",
                            strTimestamp: iso(2 * 86400), isoDate: nil)
        let vm = viewModel(with: [tomorrow])

        let live = Game(idEvent: nil, idLeague: nhl, strHomeTeam: "Avalanche", strAwayTeam: "Wild",
                        intHomeScore: "3", intAwayScore: "0", strStatus: "in",
                        strTimestamp: iso(-600), isoDate: nil)
        vm.mergeLiveIntoSchedule(liveScore(nhl: [live]))

        XCTAssertNil(vm.totalGames?.first?.intHomeScore)
    }

    func testLiveOverlayReplacesScoresInDerivedCollections() throws {
        let scheduled = Game(idEvent: "g1", idLeague: nhl, strHomeTeam: "Bruins", strAwayTeam: "Leafs",
                             strTimestamp: iso(600), isoDate: nil)
        let vm = viewModel(with: [scheduled])
        XCTAssertTrue(vm.filteredGames?.contains { $0.id == "g1" } ?? false, "fixture must be displayed")

        let live = Game(idEvent: "g1", idLeague: nhl, strHomeTeam: "Bruins", strAwayTeam: "Leafs",
                        intHomeScore: "2", intAwayScore: "1", strStatus: "in", strProgress: "2nd 10:00",
                        strTimestamp: iso(600), isoDate: nil)
        vm.mergeLiveIntoSchedule(liveScore(nhl: [live]))

        XCTAssertEqual(vm.totalGames?.first?.intHomeScore, "2")
        let filtered = try XCTUnwrap(vm.filteredGames?.first { $0.id == "g1" })
        XCTAssertEqual(filtered.intHomeScore, "2")
        XCTAssertEqual(filtered.strProgress, "2nd 10:00")
        let sectionGame = vm.sortedGamesWithTeams.flatMap(\.games).first { $0.id == "g1" }
        if let sectionGame {
            XCTAssertEqual(sectionGame.game.intHomeScore, "2")
        }
        // Scheduled timestamp is preserved, so the game doesn't move between days.
        XCTAssertEqual(filtered.strTimestamp, scheduled.strTimestamp)
    }

    func testPregameLiveDataIsIgnored() {
        let scheduled = Game(idEvent: "g1", idLeague: nhl, strHomeTeam: "Bruins", strAwayTeam: "Leafs",
                             strTimestamp: iso(3600), isoDate: nil)
        let vm = viewModel(with: [scheduled])
        let live = Game(idEvent: "g1", idLeague: nhl, strHomeTeam: "Bruins", strAwayTeam: "Leafs",
                        intHomeScore: "0", intAwayScore: "0", strStatus: "pre",
                        strTimestamp: iso(3600), isoDate: nil)
        vm.mergeLiveIntoSchedule(liveScore(nhl: [live]))
        XCTAssertNil(vm.totalGames?.first?.intHomeScore)
    }

    func testMergeThatRenamesSynthesizedIDStillPatchesDerivedCollections() throws {
        // No idEvent → `Game.id` is synthesized from fields including strAwayTeam. The
        // team-name lookup is case-insensitive, so a live copy with different casing
        // matches, and the merge takes its strAwayTeam — renaming the id.
        let scheduled = Game(idEvent: nil, idLeague: nhl, strHomeTeam: "Bruins", strAwayTeam: "Leafs",
                             strTimestamp: iso(600), isoDate: nil)
        let vm = viewModel(with: [scheduled])
        let oldID = scheduled.id
        XCTAssertTrue(vm.filteredGames?.contains { $0.id == oldID } ?? false)

        let live = Game(idEvent: nil, idLeague: nhl, strHomeTeam: "Bruins", strAwayTeam: "LEAFS",
                        intHomeScore: "5", intAwayScore: "3", strStatus: "in",
                        strTimestamp: iso(600), isoDate: nil)
        vm.mergeLiveIntoSchedule(liveScore(nhl: [live]))

        let merged = try XCTUnwrap(vm.totalGames?.first)
        XCTAssertNotEqual(merged.id, oldID, "precondition: the merge renamed the id")
        XCTAssertFalse(vm.filteredGames?.contains { $0.id == oldID } ?? true,
                       "the stale row must be replaced, not left behind")
        let patched = try XCTUnwrap(vm.filteredGames?.first { $0.id == merged.id })
        XCTAssertEqual(patched.intHomeScore, "5")
    }

    func testPatchDerivedCollectionsRewritesByPreviousID() throws {
        let scheduled = Game(idEvent: "g1", idLeague: nhl, strHomeTeam: "Bruins", strAwayTeam: "Leafs",
                             strTimestamp: iso(600), isoDate: nil)
        let vm = viewModel(with: [scheduled])
        let replacement = Game(idEvent: "g1", idLeague: nhl, strHomeTeam: "Bruins", strAwayTeam: "Leafs",
                               intHomeScore: "7", intAwayScore: "0", strStatus: "post",
                               strTimestamp: iso(600), isoDate: nil)
        vm.patchDerivedCollections(changedByID: ["g1": replacement])

        XCTAssertEqual(vm.filteredGames?.first { $0.id == "g1" }?.intHomeScore, "7")
    }
}

// MARK: - Cache

final class CacheStalenessTests: XCTestCase {

    func testValueExpiresButStaleReadSurvives() throws {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let cache = Cache<String, String>(dateProvider: { now }, entryLifetime: 60)
        cache.insert("schedule", for: "games")

        let fresh = try XCTUnwrap(cache.staleValue(for: "games"))
        XCTAssertEqual(fresh.value, "schedule")
        XCTAssertFalse(fresh.isExpired)
        XCTAssertEqual(fresh.storedAt, now)

        now = now.addingTimeInterval(61)
        let stale = try XCTUnwrap(cache.staleValue(for: "games"), "stale read must not evict")
        XCTAssertTrue(stale.isExpired)
        XCTAssertEqual(stale.value, "schedule")
        XCTAssertEqual(stale.storedAt, Date(timeIntervalSince1970: 1_000_000))

        XCTAssertNil(cache.value(for: "games"), "the strict read still treats it as expired")
    }

    func testCodableRoundTripPreservesValuesAndAge() throws {
        let written = Date().addingTimeInterval(-3 * 60 * 60)
        let cache = Cache<String, [String]>(dateProvider: { written })
        cache.insert(["a", "b"], for: "teams")

        let data = try JSONEncoder().encode(cache)
        let decoded = try JSONDecoder().decode(Cache<String, [String]>.self, from: data)

        XCTAssertEqual(decoded.value(for: "teams"), ["a", "b"])
        let entry = try XCTUnwrap(decoded.staleValue(for: "teams"))
        XCTAssertEqual(entry.storedAt.timeIntervalSince1970, written.timeIntervalSince1970, accuracy: 1)
        XCTAssertFalse(entry.isExpired)
    }

    func testRoundTripOfExpiredEntryIsReadableAsStale() throws {
        let written = Date().addingTimeInterval(-13 * 60 * 60) // past the 12h default
        let cache = Cache<String, String>(dateProvider: { written })
        cache.insert("old", for: "games")
        let decoded = try JSONDecoder().decode(Cache<String, String>.self, from: JSONEncoder().encode(cache))

        let entry = try XCTUnwrap(decoded.staleValue(for: "games"))
        XCTAssertTrue(entry.isExpired)
        XCTAssertEqual(entry.value, "old")
    }
}

// MARK: - Launch cache, ETag store, live socket

@MainActor
final class GameViewModelCoreFixTests: XCTestCase {

    private var vm: GameViewModel!

    override func setUp() async throws {
        GameViewModel.isSnapshotTesting = true
        vm = GameViewModel(appStorage: CoreFixTestSupport.storage(), favorites: Favorites())
    }

    override func tearDown() async throws {
        vm.restartTimer?.invalidate()
        vm.restartTimer = nil
        vm.webSocketTask?.cancel()
        vm.webSocketTask = nil
        vm = nil
        ScheduleETagStore.clear()
    }

    private func snapshot() -> LiveScore {
        let game = Game(idEvent: "g1", idLeague: "\(Leagues.nhl.rawValue)", strHomeTeam: "Bruins", strAwayTeam: "Leafs",
                        strTimestamp: ISO8601DateFormatter().string(from: Date()), isoDate: nil)
        return LiveScore(nhl: LiveEvent(events: [game]))
    }

    func testExpiredLaunchCacheIsShownAndFlaggedStale() {
        let storedAt = Date().addingTimeInterval(-2 * 86400)
        vm.networkState = .loading
        var loaded = GameViewModel.LaunchCaches()
        loaded.games = snapshot()
        loaded.gamesStoredAt = storedAt
        loaded.gamesExpired = true
        vm.applyLaunchCaches(loaded)

        XCTAssertEqual(vm.totalGames?.count, 1)
        XCTAssertEqual(vm.networkState, .loaded)
        XCTAssertTrue(vm.isShowingStaleCache)
        XCTAssertEqual(vm.lastSuccessfulFetch, storedAt)
        XCTAssertTrue(vm.showsStaleBanner, "no refresh in flight → the stale banner explains the old data")
    }

    func testLaunchCacheNeverOverwritesFetchedGames() {
        vm.applySnapshotFixtures(games: [Game(idEvent: "fresh", idLeague: "\(Leagues.nhl.rawValue)",
                                              strHomeTeam: "A", strAwayTeam: "B",
                                              strTimestamp: ISO8601DateFormatter().string(from: Date()), isoDate: nil)])
        var loaded = GameViewModel.LaunchCaches()
        loaded.games = snapshot()
        vm.applyLaunchCaches(loaded)
        XCTAssertEqual(vm.totalGames?.map(\.id), ["fresh"])
    }

    func testForegroundRefreshIsThrottled() {
        vm.lastSuccessfulFetch = Date().addingTimeInterval(-30)
        vm.networkState = .loaded
        XCTAssertFalse(vm.refreshOnForegroundIfNeeded())
        XCTAssertFalse(vm.isFetching)
    }

    func testETagStoreIsScopedToTheExactURL() {
        let plain = URL(string: "https://example.com/schedules")!
        let college = URL(string: "https://example.com/schedules?cfb=1")!
        ScheduleETagStore.store("\"abc\"", for: plain)
        XCTAssertEqual(ScheduleETagStore.etag(for: plain), "\"abc\"")
        XCTAssertNil(ScheduleETagStore.etag(for: college), "a validator for one variant must never be sent for another")

        ScheduleETagStore.store("\"def\"", for: college)
        XCTAssertNil(ScheduleETagStore.etag(for: plain), "only the snapshot on disk has a validator")
        ScheduleETagStore.clear()
        XCTAssertNil(ScheduleETagStore.etag(for: college))
    }

    func testStaleSocketFailureDoesNotTouchReplacement() {
        let url = URL(string: "wss://example.invalid/ws")!
        let stale = URLSession.shared.webSocketTask(with: url)
        let current = URLSession.shared.webSocketTask(with: url)
        vm.webSocketTask = current
        vm.hasNetworkPath = true

        vm.handleLiveSocketFailure(of: stale, error: URLError(.networkConnectionLost), context: "test")

        XCTAssertTrue(vm.webSocketTask === current, "a replaced socket's loop must not orphan the new one")
        XCTAssertEqual(vm.wsReconnectAttempts, 0, "and must not schedule a second reconnect")
        XCTAssertNil(vm.restartTimer)
    }

    func testCurrentSocketFailureReconnects() {
        let url = URL(string: "wss://example.invalid/ws")!
        let current = URLSession.shared.webSocketTask(with: url)
        vm.webSocketTask = current
        vm.hasNetworkPath = true

        vm.handleLiveSocketFailure(of: current, error: URLError(.networkConnectionLost), context: "test")

        XCTAssertNil(vm.webSocketTask)
        XCTAssertEqual(vm.wsReconnectAttempts, 1)
        XCTAssertNotNil(vm.restartTimer)
    }

    func testCloseOfReplacedSocketIsIgnored() {
        let url = URL(string: "wss://example.invalid/ws")!
        let stale = URLSession.shared.webSocketTask(with: url)
        let current = URLSession.shared.webSocketTask(with: url)
        vm.webSocketTask = current
        vm.hasNetworkPath = true

        vm.urlSession(URLSession.shared, webSocketTask: stale, didCloseWith: .goingAway, reason: nil)

        XCTAssertTrue(vm.webSocketTask === current)
        XCTAssertNil(vm.restartTimer)
    }

    func testBareLiveScoreFrameDecodesAsFull() throws {
        let frame = try GameViewModel.decodeLiveFrame(Data("{}".utf8))
        XCTAssertEqual(frame.kind, .full)
        XCTAssertEqual(frame.seq, 0)
    }
}
