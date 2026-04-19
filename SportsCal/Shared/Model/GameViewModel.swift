//
//  GameViewModel.swift
//  SportsCal
//
//  Created by Umar Haroon on 8/13/22.
//

import Foundation
import SwiftUI
import SportsCalModel
import OrderedCollections
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif
import Sentry
import os
#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - GameWithTeams
// Pre-computed game with team data to avoid expensive lookups during rendering
public struct GameWithTeams: Identifiable, Hashable {
    public var id: String { game.id }
    public let game: Game
    public let homeTeam: Team?
    public let awayTeam: Team?
}

// MARK: - GameDateSection
// Identifiable wrapper for date-grouped game sections (fixes ForEach index crash)
public struct GameDateSection: Identifiable {
    public var id: DateComponents { date }
    public let date: DateComponents
    public let games: [GameWithTeams]
}

@MainActor
@Observable
public class GameViewModel: NSObject {

    // Performance: Limit the number of games displayed at once
    // Users can adjust date filters to see different time windows
    static let maxDisplayedGames = 500

    var appStorage: UserDefaultStorage
    var totalGames: [Game]?
    var filteredGames: [Game]?
    var calendarGames: [Game]?
    var teamString: String? = ""
    var favoriteGames: [Game]?
    var favoriteGamesWithTeams: [GameWithTeams] = []
    var sortedGames: Array<(key: DateComponents, value: Array<Game>)> = []
    var sortedGamesWithTeams: [GameDateSection] = []
    var networkState: NetworkState = .loading
    var currentLiveInfo: LiveScore?
    var currentlyLiveSports: [SportType] = []
    var liveGameCountsBySport: [SportType: Int] = [:]
    var liveEventsWithTeams: [GameWithTeams] = []
    var todayGames: [Game] = []
    var todayGamesWithTeams: [GameWithTeams] = []
    var todayFavoriteGamesWithTeams: [GameWithTeams] = []
    var todayOtherGamesBySport: [SportType: [GameWithTeams]] = [:]
    var todayAllGamesBySport: [SportType: [GameWithTeams]] = [:]
    var f1Standings: F1Standings?

    var favorites: Favorites
    var teams: [Team] = []
    var teamsDict: [String? : [Team]] = [:]
    var teamsDictName: [String? : [Team]] = [:]
    // Optimized O(1) lookup caches - maps team ID directly to Team (not array)
    var teamByID: [String: Team] = [:]
    var teamByName: [String: Team] = [:]
    var restartTimer: Timer?
    var gamesDict: [SportType: [Game]] = [:]
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketSession: URLSession?
    private var gameCache: Cache<String, LiveScore>?
    private var teamCache: Cache<String, [Team]>?
    private var liveCache: Cache<String, LiveScore>?
    /// Cache for makeGameWithTeams() results, keyed by game ID
    private var gameWithTeamsCache: [String: GameWithTeams] = [:]
    /// Cache for gamesWithTeams(for:) results, keyed by start-of-day Date
    private var gamesWithTeamsDateCache: [Date: [GameWithTeams]] = [:]
    /// Whether a network fetch is currently in progress (visible to views for loading state).
    var isFetching: Bool { networkFetchTask != nil }
    private var networkFetchTask: Task<Void, Never>?
    private var wsReconnectAttempts = 0
    private static let maxWSReconnectAttempts = 5
    
    var currentPushToStartToken: String?
    var liveEvents: [Game] = []

    /// All live events regardless of sport preferences (used by calendar)
    var allLiveEvents: [Game] = []

    // MARK: - Batch Live Data Update
    // All 9 derived properties are recomputed in one pass to avoid redundant per-access recalculation.

    func updateLiveData() {
        let start = appStorage.debugMode ? CFAbsoluteTimeGetCurrent() : 0

        let computedLiveEvents = computeLiveEvents()
        let computedLiveEventsWithTeams = computedLiveEvents.compactMap { makeGameWithTeams($0) }
        let computedAllLiveEvents = computeAllLiveEvents()
        let computedCurrentlyLiveSports = computeCurrentlyLiveSports()
        let computedLiveGameCounts = computeLiveGameCountsBySport()
        let computedTodayGames = computeTodayGames()
        let computedTodayGamesWithTeams = computedTodayGames.compactMap { makeGameWithTeams($0) }
        let computedTodayFavorites = computedTodayGamesWithTeams.filter { favorites.contains($0.game) }
        let computedTodayOther = computeTodayOtherGamesBySport(todayGamesWithTeams: computedTodayGamesWithTeams)
        let liveIDs = Set(computedLiveEventsWithTeams.map(\.id))
        let computedTodayAll = computeTodayAllGamesBySport(todayGamesWithTeams: computedTodayGamesWithTeams, liveIDs: liveIDs)

        // Batch-assign all stored properties — SwiftUI coalesces into one update
        liveEvents = computedLiveEvents
        liveEventsWithTeams = computedLiveEventsWithTeams
        allLiveEvents = computedAllLiveEvents
        currentlyLiveSports = computedCurrentlyLiveSports
        liveGameCountsBySport = computedLiveGameCounts
        todayGames = computedTodayGames
        todayGamesWithTeams = computedTodayGamesWithTeams
        todayFavoriteGamesWithTeams = computedTodayFavorites
        todayOtherGamesBySport = computedTodayOther
        todayAllGamesBySport = computedTodayAll

        if appStorage.debugMode {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            AppLogger.viewModel.debug("updateLiveData: \(String(format: "%.1f", elapsed))ms — live: \(computedLiveEvents.count), allLive: \(computedAllLiveEvents.count), today: \(computedTodayGames.count), todayFavs: \(computedTodayFavorites.count), sports: \(computedCurrentlyLiveSports.map(\.displayName))")
        }
    }

    private func computeCurrentlyLiveSports() -> [SportType] {
        var sports: [SportType] = []
        if appStorage.shouldShowSoccer, let events = currentLiveInfo?.soccer?.events, !events.isEmpty {
            let filtered = events.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return league.isSoccer && !appStorage.hiddenCompetitions.contains(where: {$0 == league.leagueName})
            }
            if !filtered.isEmpty { sports.append(.soccer) }
        }
        if appStorage.shouldShowMLB, let events = currentLiveInfo?.mlb?.events, !events.isEmpty {
            sports.append(.mlb)
        }
        if appStorage.shouldShowNBA, let events = currentLiveInfo?.nba?.events, !events.isEmpty {
            let filtered = events.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return league.isBasketball && !appStorage.hiddenCompetitions.contains(league.leagueName)
            }
            if !filtered.isEmpty { sports.append(.basketball) }
        }
        if appStorage.shouldShowNFL, let events = currentLiveInfo?.nfl?.events, !events.isEmpty {
            sports.append(.nfl)
        }
        if appStorage.shouldShowNHL, let events = currentLiveInfo?.nhl?.events, !events.isEmpty {
            sports.append(.hockey)
        }
        if appStorage.shouldShowGolf, let events = currentLiveInfo?.golf?.events, !events.isEmpty {
            sports.append(.golf)
        }
        if appStorage.shouldShowTennis, let events = currentLiveInfo?.tennis?.events, !events.isEmpty {
            sports.append(.tennis)
        }
        if appStorage.shouldShowRacing, let events = currentLiveInfo?.racing?.events, !events.isEmpty {
            sports.append(.racing)
        }
        return sports
    }

    private func computeLiveGameCountsBySport() -> [SportType: Int] {
        var counts: [SportType: Int] = [:]

        if let soccerEvents = currentLiveInfo?.soccer?.events {
            let filteredSoccer = soccerEvents.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return league.isSoccer && !appStorage.hiddenCompetitions.contains(where: {$0 == league.leagueName})
            }
            if !filteredSoccer.isEmpty {
                counts[.soccer] = filteredSoccer.count
            }
        }

        if let mlbEvents = currentLiveInfo?.mlb?.events {
            let filteredMLB = mlbEvents.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return false }
                return true
            }
            if !filteredMLB.isEmpty {
                counts[.mlb] = filteredMLB.count
            }
        }

        if let nbaEvents = currentLiveInfo?.nba?.events {
            let filteredNBA = nbaEvents.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return league.isBasketball && !appStorage.hiddenCompetitions.contains(league.leagueName)
            }
            if !filteredNBA.isEmpty {
                counts[.basketball] = filteredNBA.count
            }
        }

        if let nflEvents = currentLiveInfo?.nfl?.events {
            let filteredNFL = nflEvents.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return false }
                return true
            }
            if !filteredNFL.isEmpty {
                counts[.nfl] = filteredNFL.count
            }
        }

        if let nhlEvents = currentLiveInfo?.nhl?.events {
            let filteredNHL = nhlEvents.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return false }
                return true
            }
            if !filteredNHL.isEmpty {
                counts[.hockey] = filteredNHL.count
            }
        }

        if let golfEvents = currentLiveInfo?.golf?.events {
            let filteredGolf = golfEvents.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return false }
                return true
            }
            if !filteredGolf.isEmpty {
                counts[.golf] = filteredGolf.count
            }
        }

        if let tennisEvents = currentLiveInfo?.tennis?.events {
            let filteredTennis = tennisEvents.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return false }
                return true
            }
            if !filteredTennis.isEmpty {
                counts[.tennis] = filteredTennis.count
            }
        }

        if let racingEvents = currentLiveInfo?.racing?.events {
            let filteredRacing = racingEvents.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return false }
                return true
            }
            if !filteredRacing.isEmpty {
                counts[.racing] = filteredRacing.count
            }
        }

        return counts
    }

    private func computeTodayGames() -> [Game] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        return (filteredGames ?? []).filter { game in
            // For multi-session events (F1), check if any session falls on today
            if !game.sessionDates.isEmpty {
                return game.sessionDates.contains { date in
                    date >= today && date < tomorrow
                }
            }
            guard let gameDate = game.standardDate else { return false }
            return gameDate >= today && gameDate < tomorrow
        }
    }

    private func computeTodayOtherGamesBySport(todayGamesWithTeams: [GameWithTeams]) -> [SportType: [GameWithTeams]] {
        let nonFavorites = todayGamesWithTeams.filter { gameWithTeams in
            !favorites.contains(gameWithTeams.game)
        }
        var grouped: [SportType: [GameWithTeams]] = [:]
        for gameWithTeams in nonFavorites {
            guard let leagueString = gameWithTeams.game.idLeague,
                  let intLeague = Int(leagueString),
                  let league = Leagues(rawValue: intLeague) else { continue }
            let sport = SportType(league: league)
            if grouped[sport] != nil {
                grouped[sport]?.append(gameWithTeams)
            } else {
                grouped[sport] = [gameWithTeams]
            }
        }
        return grouped
    }

    private func computeTodayAllGamesBySport(todayGamesWithTeams: [GameWithTeams], liveIDs: Set<String>) -> [SportType: [GameWithTeams]] {
        let nonLive = todayGamesWithTeams.filter { !liveIDs.contains($0.id) }
        var grouped: [SportType: [GameWithTeams]] = [:]
        for gameWithTeams in nonLive {
            guard let leagueString = gameWithTeams.game.idLeague,
                  let intLeague = Int(leagueString),
                  let league = Leagues(rawValue: intLeague) else { continue }
            let sport = SportType(league: league)
            grouped[sport, default: []].append(gameWithTeams)
        }
        // Sort each group: favorites first, then by game date
        for (sport, games) in grouped {
            grouped[sport] = games.sorted { a, b in
                let aFav = favorites.contains(a.game)
                let bFav = favorites.contains(b.game)
                if aFav != bFav { return aFav }
                return (a.game.standardDate ?? .distantPast) < (b.game.standardDate ?? .distantPast)
            }
        }
        return grouped
    }

    private func computeLiveEvents() -> [Game] {
        var games: [Game] = []
        if appStorage.shouldShowSoccer {
            var soccerGames = currentLiveInfo?.soccer?.events
            soccerGames = soccerGames?.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return league.isSoccer && !appStorage.hiddenCompetitions.contains(where: {$0 == league.leagueName})
            }
            if let soccerGames {
                games.append(contentsOf: soccerGames)
            }
        }
        if appStorage.shouldShowMLB {
            var baseballGames = currentLiveInfo?.mlb?.events
            baseballGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return true }
                return false
            })
            if let baseballGames {
                games.append(contentsOf: baseballGames)
            }
        }
        if appStorage.shouldShowNBA {
            var basketballGames = currentLiveInfo?.nba?.events
            basketballGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else {
                    return true
                }
                return !league.isBasketball || appStorage.hiddenCompetitions.contains(league.leagueName)
            })
            if let basketballGames {
                games.append(contentsOf: basketballGames)
            }
        }
        if appStorage.shouldShowNFL {
            var nflGames = currentLiveInfo?.nfl?.events
            nflGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return true }
                return false
            })
            if let nflGames {
                games.append(contentsOf: nflGames)
            }
        }
        if appStorage.shouldShowNHL {
            var nhlGames = currentLiveInfo?.nhl?.events
            nhlGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return true }
                return false
            })
            if let nhlGames {
                games.append(contentsOf: nhlGames)
            }
        }
        if appStorage.shouldShowGolf {
            var golfGames = currentLiveInfo?.golf?.events
            golfGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return true }
                return false
            })
            if let golfGames {
                games.append(contentsOf: golfGames)
            }
        }
        if appStorage.shouldShowTennis {
            var tennisGames = currentLiveInfo?.tennis?.events
            tennisGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return true }
                return false
            })
            if let tennisGames {
                games.append(contentsOf: tennisGames)
            }
        }
        if appStorage.shouldShowRacing {
            var racingGames = currentLiveInfo?.racing?.events
            racingGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return true }
                return false
            })
            if let racingGames {
                games.append(contentsOf: racingGames)
            }
        }
        return Array(OrderedSet(games))
    }

    private func computeAllLiveEvents() -> [Game] {
        let allSportEvents: [[Game]?] = [
            currentLiveInfo?.nba?.events,
            currentLiveInfo?.mlb?.events,
            currentLiveInfo?.soccer?.events,
            currentLiveInfo?.nfl?.events,
            currentLiveInfo?.nhl?.events,
            currentLiveInfo?.golf?.events,
            currentLiveInfo?.tennis?.events,
            currentLiveInfo?.racing?.events
        ]
        let games = allSportEvents.compactMap { $0 }.flatMap { $0 }.filter { game in
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let league = Leagues(rawValue: intLeague) else { return false }
            if league.isSoccer {
                return !appStorage.hiddenCompetitions.contains(league.leagueName)
            }
            return true
        }
        return Array(OrderedSet(games))
    }

    init(appStorage: UserDefaultStorage, favorites: Favorites, totalGames: [Game]? = nil, filteredGames: [Game]? = nil, teamString: String? = "", favoriteGames: [Game]? = nil, sortedGames: Array<(key: DateComponents, value: Array<Game>)> = [], networkState: NetworkState = .loading) {
        self.appStorage = appStorage
        self.favorites = favorites
        self.totalGames = totalGames
        self.filteredGames = filteredGames
        self.teamString = teamString
        self.favoriteGames = favoriteGames
        self.sortedGames = sortedGames
        self.networkState = networkState
        self.gamesDict = [:]
        
        let folderURLs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        var gameFileURL = folderURLs[0]
        gameFileURL.appendPathComponent("games" + ".cache")
        var teamFileURL = folderURLs[0]
        teamFileURL.appendPathComponent("teams" + ".cache")
        do {
            let data = try JSONDecoder().decode(Cache<String, LiveScore>.self, from: Data(contentsOf: gameFileURL))
            self.gameCache = data
            let teamData = try JSONDecoder().decode(Cache<String, [Team]>.self, from: Data(contentsOf: teamFileURL))
            self.teamCache = teamData
        } catch let error {
            self.gameCache = Cache<String, LiveScore>()
            self.teamCache = Cache<String, [Team]>()
            self.liveCache = Cache<String, LiveScore>(entryLifetime: 15 * 60)
            AppLogger.viewModel.error("Cache load failed: \(error.localizedDescription)")
        }

        // Call super.init() after all stored properties are initialized
        super.init()

        self.webSocketSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

        var hasCachedData = false
        if let cacheGames = gameCache?.value(for: "games") {
            setGames(result: cacheGames)
            hasCachedData = true
        }
        if let cacheTeams = teamCache?.value(for: "teams") {
            self.teams = cacheTeams
            buildTeamLookupCaches()
        }
        // If we loaded cached games, show them immediately instead of a loading spinner
        if hasCachedData {
            self.networkState = .loaded
        }
        getInfo(backgroundRefresh: hasCachedData)
        
        // Note: With @Observable, changes to appStorage properties are automatically tracked
        // No need for manual observation like the old objectWillChange.sink pattern
    }
    
    private func handleLiveGames() async throws {
        AppLogger.networking.info("Getting live games")
        var liveInfo = try await NetworkHandler.getLiveSnapshot(debug: appStorage.debugMode)
        // Merge live scores into schedule before filtering out completed games
        mergeLiveIntoSchedule(liveInfo)
        liveInfo.removeNonStarting()
        liveInfo.removeOtherInfo()
        self.currentLiveInfo = liveInfo
        updateLiveData()
//        print("found", self.currentLiveInfo?.mlb?.events.count, "mlb games")
//        print("found", self.currentLiveInfo?.nba?.events.count, "nba games")
//        print("found", self.currentLiveInfo?.nfl?.events.count, "nfl games")
//        print("found", self.currentLiveInfo?.nhl?.events.count, "nhl games")
//        print("found", self.currentLiveInfo?.soccer?.events.count, "soccer games")
//        print("found", self.currentLiveInfo?.golf?.events.count, "golf games")
//        print("found", self.currentLiveInfo?.tennis?.events.count, "tennis games")
        if let liveInfo = currentLiveInfo {
            liveCache?.insert(liveInfo, for: "live")
        }
        try liveCache?.saveToDisk(with: "live") 
    }
    
    private func handleTeams() async throws {
        AppLogger.networking.info("Getting teams")
        async let teams = NetworkHandler.getTeams(debug: appStorage.debugMode)
        self.teams = try await teams
        buildTeamLookupCaches()
        teamCache?.insert(self.teams, for: "teams")
        try teamCache?.saveToDisk(with: "teams")
    }

    /// Builds optimized O(1) lookup caches for teams
    /// This replaces multiple dictionary lookups with single hash table access
    private func buildTeamLookupCaches() {
        // Invalidate GameWithTeams cache since team data changed
        gameWithTeamsCache.removeAll()
        gamesWithTeamsDateCache.removeAll()

        // Build legacy dictionaries for backwards compatibility
        var teamsDict = Dictionary(grouping: self.teams, by: \.idTeam)
        teamsDict = teamsDict.mapValues { teams in
            return Array(Set(teams))
        }
        self.teamsDict = teamsDict

        var teamsDictName = Dictionary(grouping: self.teams, by: \.strTeam)
        teamsDictName = teamsDictName.mapValues { teams in
            return Array(Set(teams))
        }
        self.teamsDictName = teamsDictName

        // Build optimized O(1) lookup caches
        // These map directly to a single Team instead of an array
        var byID: [String: Team] = [:]
        var byName: [String: Team] = [:]

        byID.reserveCapacity(teams.count)
        byName.reserveCapacity(teams.count)

        for team in teams {
            if let id = team.idTeam {
                byID[id] = team
            }
            if let name = team.strTeam {
                byName[name] = team
            }
            // Also index by each alternate name (comma-separated)
            if let alternate = team.strAlternate {
                for altName in alternate.components(separatedBy: ", ") {
                    let trimmed = altName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        byName[trimmed] = team
                    }
                }
            }
        }

        self.teamByID = byID
        self.teamByName = byName

        if appStorage.debugMode {
            AppLogger.viewModel.debug("Built team lookup caches: \(byID.count) by ID, \(byName.count) by name")
        }
    }
    
    private func handleLiveWebsocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        wsReconnectAttempts = 0
        webSocketTask = NetworkHandler.connectWebSocketForLive(session: webSocketSession!, debug: appStorage.debugMode)
        webSocketTask?.resume()
        Task { @MainActor [weak self] in
            do {
                try await self?.receiveMessages()
            } catch {
                AppLogger.networking.error("WebSocket receive error: \(error.localizedDescription)")
                self?.webSocketTask = nil
                self?.reconnectWebSocketOnly()
            }
        }
    }

    private func reconnectWebSocketOnly() {
        guard wsReconnectAttempts < Self.maxWSReconnectAttempts else {
            if appStorage.debugMode {
                AppLogger.networking.notice("WebSocket max reconnect attempts (\(Self.maxWSReconnectAttempts)) reached, stopping")
            }
            return
        }
        wsReconnectAttempts += 1
        let delay = min(Double(wsReconnectAttempts * wsReconnectAttempts) * 2, 60) // exponential backoff: 2, 8, 18, 32, 50s
        if appStorage.debugMode {
            AppLogger.networking.info("WebSocket reconnect attempt \(self.wsReconnectAttempts)/\(Self.maxWSReconnectAttempts) in \(delay)s")
        }
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.restartTimer = nil
            self?.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self?.webSocketTask = nil
            self?.webSocketTask = NetworkHandler.connectWebSocketForLive(session: self?.webSocketSession, debug: self?.appStorage.debugMode ?? false)
            self?.webSocketTask?.resume()
            Task { @MainActor [weak self] in
                do {
                    try await self?.receiveMessages()
                } catch {
                    AppLogger.networking.error("WebSocket receive error (reconnect): \(error.localizedDescription)")
                    self?.webSocketTask = nil
                    self?.reconnectWebSocketOnly()
                }
            }
        }
    }
    
    func shouldAddTask(sport: SportType) -> Bool {
        switch sport {
        case .basketball:
            return appStorage.shouldShowNBA
        case .soccer:
            return appStorage.shouldShowSoccer
        case .hockey:
            return appStorage.shouldShowNHL
        case .mlb:
            return appStorage.shouldShowMLB
        case .nfl:
            return appStorage.shouldShowNFL
        case .golf:
            return appStorage.shouldShowGolf
        case .tennis:
            return appStorage.shouldShowTennis
        case .racing:
            return appStorage.shouldShowRacing
        }
    }
    
    fileprivate func handleGames() async throws {
        let groupResult = try await withThrowingTaskGroup(of: [SportType: LiveEvent].self) { group in
            var events: [SportType: LiveEvent] = [:]
            // Fetch all sports so the calendar can show everything
            for sport in SportType.allCases {
                if shouldAddTask(sport: sport) {
                    AppLogger.networking.info("Requesting schedule for \(sport.displayName)")
                    group.addTask {
                        do {
                            return [sport: try await NetworkHandler.getScheduleFor(sport: sport, debug: self.appStorage.debugMode)]
                        } catch {
                            AppLogger.networking.error("Failed to fetch schedule for \(sport.displayName): \(error.localizedDescription)")
                            return [:]
                        }
                    }
                }
            }
            for try await schedule in group {
                events.merge(schedule) { liveEvent1, liveEvent2 in
                    liveEvent2
                }
            }
            return LiveScore(nba: events[.basketball] ?? nil, mlb: events[.mlb] ?? nil, soccer: events[.soccer] ?? nil, nfl: events[.nfl] ?? nil, nhl: events[.hockey] ?? nil, golf: events[.golf] ?? nil, tennis: events[.tennis] ?? nil, racing: events[.racing] ?? nil)
        }
        
        gameCache?.insert(groupResult, for: "games")
        try gameCache?.saveToDisk(with: "games")
        setGames(result: groupResult, skipLiveUpdate: true)
    }
    
    @objc
    private func getData() async {
        // Phase 1: Fetch teams + live snapshot first (fast), then connect WebSocket immediately.
        // This ensures live games appear without waiting for full schedule fetch.
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do { try await self.handleTeams() }
                catch { AppLogger.networking.error("handleTeams failed: \(error.localizedDescription)") }
            }
            group.addTask {
                do { try await self.handleLiveGames() }
                catch { AppLogger.networking.error("handleLiveGames failed: \(error.localizedDescription)") }
            }
            await group.waitForAll()
        }
        // Re-run after both teams and live data are available so live events render with team badges
        updateLiveData()
        // Connect WebSocket only if there are live/upcoming games
        ensureWebSocketConnected()

        // Phase 2: Fetch full schedules (slower, per-sport)
        do { try await self.handleGames() }
        catch { AppLogger.networking.error("handleGames failed: \(error.localizedDescription)") }
        // Re-evaluate WebSocket now that we have schedule data
        ensureWebSocketConnected()
        #if canImport(ActivityKit) && os(iOS)
        registerPushToStartIfNeeded()
        observeLiveActivities()
        preCacheFavoriteTeamBadges()
        #endif
        appStorage.cleanupExpiredAutoFollows(games: totalGames ?? [])
        networkState = .loaded
        networkFetchTask = nil
    }

    @objc
    func receiveMessages() async throws {
        while let webSocket = webSocketTask {
            let webSocketMessage = try await webSocket.receive()
            wsReconnectAttempts = 0 // Reset on successful receive
            switch webSocketMessage {
            case .string(let jsonString):
                if let jsonData = jsonString.data(using: .utf8) {
                    var newLiveInfo = try JSONDecoder().decode(LiveScore.self, from: jsonData)
                    // Merge live scores (including completed games) into schedule before filtering
                    mergeLiveIntoSchedule(newLiveInfo)
                    newLiveInfo.removeNonStarting()
                    newLiveInfo.removeOtherInfo()
                    withAnimation {
                        if let currentLiveInfo = currentLiveInfo, currentLiveInfo != newLiveInfo {
                            self.currentLiveInfo = newLiveInfo
                        } else if currentLiveInfo == nil {
                            self.currentLiveInfo = newLiveInfo
                        }
                        updateLiveData()
                    }
                    #if canImport(ActivityKit) && os(iOS)
                    Task { @MainActor in
                        try await updateLiveActivities()
                        checkAutoFollowedGamesForLiveStart()
                    }
                    #endif
                }
            case .data(_):
                break
            @unknown default:
                break
            }
        }
    }
    
    /// Merges live WebSocket data into totalGames so schedule rows reflect current scores/status.
    /// Called before removeNonStarting() so completed games also get their final scores merged.
    private func mergeLiveIntoSchedule(_ liveScore: LiveScore) {
        guard var games = totalGames, !games.isEmpty else { return }

        let allLive = [liveScore.nba?.events, liveScore.mlb?.events, liveScore.soccer?.events,
                       liveScore.nfl?.events, liveScore.nhl?.events, liveScore.golf?.events,
                       liveScore.tennis?.events, liveScore.racing?.events]
            .compactMap { $0 }.flatMap { $0 }
        guard !allLive.isEmpty else { return }

        // Build lookups for matching: by event ID (most reliable) and by team names (fallback)
        var liveByEventID: [String: Game] = [:]
        var liveByTeams: [String: Game] = [:]
        for game in allLive {
            if let eventID = game.idEvent {
                liveByEventID[eventID] = game
            }
            let key = "\(game.strHomeTeam.lowercased())|\(game.strAwayTeam.lowercased())|\(game.idLeague ?? "")"
            liveByTeams[key] = game
        }

        var changed = false
        for i in games.indices {
            let scheduled = games[i]
            // Match by event ID first (reliable for F1/golf/tennis where team names change)
            // Fall back to team names for backwards compatibility
            let live: Game
            if let eventID = scheduled.idEvent, let match = liveByEventID[eventID] {
                live = match
            } else {
                let key = "\(scheduled.strHomeTeam.lowercased())|\(scheduled.strAwayTeam.lowercased())|\(scheduled.idLeague ?? "")"
                guard let match = liveByTeams[key] else { continue }
                live = match
            }

            // Only update if the live data has meaningful status (not pre-game)
            guard live.strStatus != "pre" && live.strStatus != "NS" else { continue }

            // Only update if something actually changed
            if scheduled.intHomeScore == live.intHomeScore &&
               scheduled.intAwayScore == live.intAwayScore &&
               scheduled.strStatus == live.strStatus &&
               scheduled.strProgress == live.strProgress &&
               scheduled.isCompleted == live.isCompleted { continue }

            games[i] = Game(
                idLiveScore: scheduled.idLiveScore, idEvent: scheduled.idEvent,
                idLeague: scheduled.idLeague,
                idHomeTeam: scheduled.idHomeTeam, idAwayTeam: scheduled.idAwayTeam,
                strHomeTeam: scheduled.strHomeTeam, strAwayTeam: live.strAwayTeam,
                strHomeTeamBadge: live.strHomeTeamBadge ?? scheduled.strHomeTeamBadge,
                strAwayTeamBadge: live.strAwayTeamBadge ?? scheduled.strAwayTeamBadge,
                intHomeScore: live.intHomeScore ?? scheduled.intHomeScore,
                intAwayScore: live.intAwayScore ?? scheduled.intAwayScore,
                strStatus: live.strStatus ?? scheduled.strStatus,
                strProgress: live.strProgress ?? scheduled.strProgress,
                strTimestamp: scheduled.strTimestamp,
                lastPlay: live.lastPlay ?? scheduled.lastPlay,
                homeLinescores: live.homeLinescores ?? scheduled.homeLinescores,
                awayLinescores: live.awayLinescores ?? scheduled.awayLinescores,
                homeLeaders: live.homeLeaders ?? scheduled.homeLeaders,
                awayLeaders: live.awayLeaders ?? scheduled.awayLeaders,
                isCompleted: live.isCompleted ?? scheduled.isCompleted,
                isoDate: scheduled.isoDate,
                leaderboardEntries: live.leaderboardEntries ?? scheduled.leaderboardEntries,
                sessions: live.sessions ?? scheduled.sessions,
                venueName: live.venueName ?? scheduled.venueName,
                circuitInfo: live.circuitInfo ?? scheduled.circuitInfo,
                homeSeed: live.homeSeed ?? scheduled.homeSeed,
                awaySeed: live.awaySeed ?? scheduled.awaySeed
            )
            changed = true
        }

        if changed {
            totalGames = games
            // Rebuild filtered games and caches
            gameWithTeamsCache.removeAll()
            gamesWithTeamsDateCache.removeAll()
            filterSports(force: true, skipLiveUpdate: true)
        }
    }

    func setGames(result: LiveScore, skipLiveUpdate: Bool = false) {
        // Invalidate caches since games changed
        gameWithTeamsCache.removeAll()
        gamesWithTeamsDateCache.removeAll()

        totalGames = [result.nhl?.events, result.nfl?.events, result.soccer?.events, result.mlb?.events, result.nba?.events, result.golf?.events, result.tennis?.events, result.racing?.events]
            .compactMap({$0})
            .flatMap({$0})
        if let standings = result.f1Standings {
            f1Standings = standings
        }
        filterSports(force: true, skipLiveUpdate: skipLiveUpdate)
    }
    
    func handleSports(force: Bool = false) {
        if force {
            totalGames = totalGames?.filter({ game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return false }
                return true
            }) ?? []
            gamesDict = Dictionary(grouping: totalGames ?? [], by: { game in
                SportType(league: Leagues.init(rawValue: Int(game.idLeague!)!)!)
            })
        }
    }
    
    func getGamesFromUserPreferences() -> [Game] {
        var allGames: [Game] = []
        if appStorage.shouldShowSoccer {
            let soccerGames = (gamesDict[.soccer] ?? []).filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return league.isSoccer && !appStorage.hiddenCompetitions.contains(where: {$0 == league.leagueName})
            }
            allGames.append(contentsOf: applyFavoritesFilter(soccerGames, favoritesOnly: appStorage.favoritesOnlySoccer))
        }
        if appStorage.shouldShowMLB {
            let games = gamesDict[.mlb] ?? []
            allGames.append(contentsOf: applyFavoritesFilter(games, favoritesOnly: appStorage.favoritesOnlyMLB))
        }
        if appStorage.shouldShowNBA {
            if let basketballGames = gamesDict[.basketball] {
                let filtered = basketballGames.filter { game in
                    guard let leagueString = game.idLeague,
                          let intLeague = Int(leagueString),
                          let league = Leagues(rawValue: intLeague) else { return false }
                    return league.isBasketball && !appStorage.hiddenCompetitions.contains(league.leagueName)
                }
                allGames.append(contentsOf: applyFavoritesFilter(filtered, favoritesOnly: appStorage.favoritesOnlyNBA))
            }
        }
        if appStorage.shouldShowNFL {
            let games = gamesDict[.nfl] ?? []
            allGames.append(contentsOf: applyFavoritesFilter(games, favoritesOnly: appStorage.favoritesOnlyNFL))
        }
        if appStorage.shouldShowNHL {
            let games = gamesDict[.hockey] ?? []
            allGames.append(contentsOf: applyFavoritesFilter(games, favoritesOnly: appStorage.favoritesOnlyNHL))
        }
        if appStorage.shouldShowGolf {
            let games = gamesDict[.golf] ?? []
            allGames.append(contentsOf: applyFavoritesFilter(games, favoritesOnly: appStorage.favoritesOnlyGolf))
        }
        if appStorage.shouldShowTennis {
            let games = gamesDict[.tennis] ?? []
            allGames.append(contentsOf: applyFavoritesFilter(games, favoritesOnly: appStorage.favoritesOnlyTennis))
        }
        if appStorage.shouldShowRacing {
            let games = gamesDict[.racing] ?? []
            allGames.append(contentsOf: applyFavoritesFilter(games, favoritesOnly: appStorage.favoritesOnlyRacing))
        }
        return allGames
    }

    private func applyFavoritesFilter(_ games: [Game], favoritesOnly: Bool) -> [Game] {
        guard favoritesOnly else { return games }
        return games.filter { favorites.matches($0) }
    }
    
    func showGame(game: Game) -> Bool {
        // if hidePastEvents
        // if game in past
        // For multi-session events (F1), use the latest session date (Race day) so
        // the event isn't hidden while the weekend is still ongoing or just finished.
        guard let date = game.effectiveEndDate else { return false }
        if date.timeIntervalSinceNow < 0 {
            if self.appStorage.hidePastEvents{
                return false
            } else {
                switch self.appStorage.hidePastGamesDuration {
                case .oneWeek:
                    guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                    return (days >= -7)
                case .twoWeeks:
                    guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                    return (days >= -14)
                case .threeWeeks:
                    guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                    return (days >= -21)
                case .oneMonth:
                    guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                    return (month1 >= -1)
                case .twoMonths:
                    guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                    return (month1 >= -2)
                case .sixMonths:
                    guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                    return (month1 >= -6)
                case .oneYear:
                    guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                    return (month1 >= -12)
                case .oneDay:
                    guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                    return (days >= -1)
                }
            }
        }
        
        switch self.appStorage.durations {
        case .oneWeek:
            guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
            return (days <= 7)
        case .twoWeeks:
            guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
            return (days <= 14)
        case .threeWeeks:
            guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
            return (days <= 21)
        case .oneMonth:
            guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
            return (month1 < 1)
        case .twoMonths:
            guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
            return (month1 < 2)
        case .sixMonths:
            guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
            return (month1 < 2)
        case .oneYear:
            guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
            return (month1 < 12)
        case .oneDay:
            guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
            return (days < 1)
        }
        
    }
    
    func isValidInPast(game: Game) -> Bool {
        guard let date = game.standardDate else { return true }
        var isValidForPastDuration: Bool = false
        if self.appStorage.hidePastEvents {
            return date.timeIntervalSinceNow > 0
        } else {
            switch self.appStorage.hidePastGamesDuration {
            case .oneWeek:
                guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                isValidForPastDuration = (days >= -7)
            case .twoWeeks:
                guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                isValidForPastDuration = (days >= -14)
            case .threeWeeks:
                guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                isValidForPastDuration = (days >= -21)
            case .oneMonth:
                guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                isValidForPastDuration = (month1 >= -1)
            case .twoMonths:
                guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                isValidForPastDuration = (month1 >= -2)
            case .sixMonths:
                guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                isValidForPastDuration = (month1 >= -6)
            case .oneYear:
                guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                isValidForPastDuration = (month1 >= -12)
            case .oneDay:
                guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                isValidForPastDuration = (days >= -1)
            }
        }
        return isValidForPastDuration
    }
    
    func isValidInFuture(game: Game) -> Bool {
        guard let date = game.standardDate else { return true }
        var isValidForFutureDuration: Bool = false
        switch self.appStorage.durations {
        case .oneWeek:
            guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
            isValidForFutureDuration = (days <= 7)
        case .twoWeeks:
            guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
            isValidForFutureDuration = (days <= 14)
        case .threeWeeks:
            guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
            isValidForFutureDuration = (days <= 21)
        case .oneMonth:
            guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
            isValidForFutureDuration = (month1 < 1)
        case .twoMonths:
            guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
            isValidForFutureDuration = (month1 < 2)
        case .sixMonths:
            guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
            isValidForFutureDuration = (month1 < 2)
        case .oneYear:
            guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
            isValidForFutureDuration = (month1 < 12)
        case .oneDay:
            guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
            isValidForFutureDuration = (days < 1)
        }
        return isValidForFutureDuration
    }
    
    func filterAndSortGamesFromUserPreferences(games: [Game]) -> [Game] {
        return games.filter({ game -> Bool in
            return showGame(game: game)
        })
        .sorted { lhs, rhs in
            lhs.standardDate ?? .now < rhs.standardDate ?? .now
        }
    }
    
    func filterSports(searchString: String? = nil, force: Bool = false, skipLiveUpdate: Bool = false) {
        // Invalidate date-keyed cache since filtered games are changing
        gamesWithTeamsDateCache.removeAll()

        if appStorage.debugMode {
            AppLogger.viewModel.debug("Sports filter changed — NFL:\(self.appStorage.shouldShowNFL) NBA:\(self.appStorage.shouldShowNBA) NHL:\(self.appStorage.shouldShowNHL) Soccer:\(self.appStorage.shouldShowSoccer) MLB:\(self.appStorage.shouldShowMLB) Golf:\(self.appStorage.shouldShowGolf) Tennis:\(self.appStorage.shouldShowTennis) Racing:\(self.appStorage.shouldShowRacing)")
        }
        if force {
            totalGames = totalGames?.filter({ game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return false }
                return true
            }) ?? []
            gamesDict = Dictionary(grouping: totalGames ?? [], by: { game in
                SportType(league: Leagues.init(rawValue: Int(game.idLeague!)!)!)
            })
        }
        let userPrefGames = getGamesFromUserPreferences()
        filteredGames = filterAndSortGamesFromUserPreferences(games: userPrefGames)
        // Calendar shows ALL sports but respects hidden soccer competitions
        let allValidGames = (totalGames ?? []).filter { game in
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let league = Leagues(rawValue: intLeague) else { return false }
            if league.isSoccer {
                return !appStorage.hiddenCompetitions.contains(league.leagueName)
            }
            return true
        }
        calendarGames = allValidGames.sorted { ($0.standardDate ?? .now) < ($1.standardDate ?? .now) }

        rebuildSportCountsCache()
        AppLogger.viewModel.info("Total games: \(self.totalGames?.count ?? 0), filtered: \(self.filteredGames?.count ?? 0)")
        handleSearch(searchString: searchString)
        sortByDate()
        setFavorites()
        if !skipLiveUpdate {
            updateLiveData()
        }

        // Write trimmed snapshot for widget extension off main actor
        let snapshotGames = filteredGames ?? []
        let snapshotTeams = teams
        Task.detached(priority: .utility) {
            WidgetDataStore.writeSnapshot(games: snapshotGames, teams: snapshotTeams)
        }

        // Index games in Spotlight off main actor
        #if !WIDGET_EXTENSION
        let spotlightGames = snapshotGames
        let spotlightFavorites = favorites.teams
        Task.detached(priority: .utility) {
            SpotlightIndexer.indexGames(spotlightGames, favorites: spotlightFavorites)
        }

        // Donate intents for proactive Siri suggestions
        donateIntents(games: snapshotGames)
        #endif
    }
    #if !WIDGET_EXTENSION
    private func donateIntents(games: [Game]) {
        let favoriteTeams = favorites.teams
        let enabledSports = appStorage.enabledSports
        Task.detached(priority: .utility) {
            let manager = IntentDonationManager.shared

            // Donate TrackGameIntent for favorite teams with upcoming games today/tomorrow
            let calendar = Calendar.current
            let now = Date()
            guard let endDate = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) else { return }

            for game in games {
                guard let gameDate = game.standardDate,
                      gameDate >= now && gameDate < endDate else { continue }
                let isHomeFav = favoriteTeams.contains(game.strHomeTeam)
                let isAwayFav = favoriteTeams.contains(game.strAwayTeam)
                guard isHomeFav || isAwayFav else { continue }

                let teamName = isHomeFav ? game.strHomeTeam : game.strAwayTeam
                var intent = TrackGameIntent()
                intent.team = TeamEntity(id: teamName, name: teamName)
                try? await manager.donate(intent: intent)
            }

            // Donate OpenSportIntent for enabled sports
            for sport in enabledSports {
                var intent = OpenSportIntent()
                intent.sport = SportAppEnum(sportType: sport)
                try? await manager.donate(intent: intent)
            }
        }
    }
    #endif

    func sortByDate() {
        let groupDic = Dictionary(grouping: filteredGames ?? []) { game -> DateComponents in
            // For multi-session events (F1), group by the effective end date (Race day)
            let gameDate = game.effectiveEndDate ?? game.standardDate ?? .now
            let date2 = Calendar.current.dateComponents([.day, .year, .month, .calendar], from: gameDate)
            return date2
        }
        let sorted = groupDic.sorted(by: {
            return $0.key.date! < $1.key.date!
        })

        // Performance: Limit total games displayed to prevent UI freezing
        var limitedSorted: Array<(key: DateComponents, value: Array<Game>)> = []
        var totalCount = 0
        for section in sorted {
            if totalCount >= Self.maxDisplayedGames { break }
            let remainingSlots = Self.maxDisplayedGames - totalCount
            if section.value.count <= remainingSlots {
                limitedSorted.append(section)
                totalCount += section.value.count
            } else {
                // Partial section to reach the limit
                let limitedGames = Array(section.value.prefix(remainingSlots))
                limitedSorted.append((key: section.key, value: limitedGames))
                totalCount += limitedGames.count
                break
            }
        }

        if totalCount >= Self.maxDisplayedGames {
            AppLogger.viewModel.notice("Performance: Limited display to \(totalCount) games out of \(self.filteredGames?.count ?? 0) filtered games")
        }

        // Pre-compute games with team data to avoid expensive lookups during rendering
        let sortedWithTeams = limitedSorted.compactMap { (key, games) -> GameDateSection? in
            let gamesWithTeams = games.compactMap { game -> GameWithTeams? in
                guard let gwt = makeGameWithTeams(game) else {
                    if appStorage.debugMode {
                        AppLogger.viewModel.notice("Failed to find teams for game: \(game.strHomeTeam) @ \(game.strAwayTeam), idHome: \(game.idHomeTeam ?? "nil"), idAway: \(game.idAwayTeam ?? "nil")")
                    }
                    return nil
                }
                return gwt
            }
            // Only include sections that have at least one game with team data
            guard !gamesWithTeams.isEmpty else {
                if appStorage.debugMode {
                    AppLogger.viewModel.notice("Section \(key.date?.formatted() ?? "unknown") has no games with team data")
                }
                return nil
            }
            return GameDateSection(date: key, games: gamesWithTeams)
        }

        AppLogger.viewModel.info("Display stats: \(sortedWithTeams.count) sections, total games with teams: \(sortedWithTeams.reduce(0) { $0 + $1.games.count })")
        AppLogger.viewModel.info("Teams loaded: \(self.teams.count), teamsDict entries: \(self.teamsDict.count)")

        // Populate gamesWithTeams date cache as a byproduct of sortByDate
        // This uses ALL user-pref games (not limited), keyed by start-of-day
        var dateCache: [Date: [GameWithTeams]] = [:]
        let calendar = Calendar.current
        let userPrefGames = getGamesFromUserPreferences()
        for game in userPrefGames {
            guard let gameDate = game.standardDate else { continue }
            let dayStart = calendar.startOfDay(for: gameDate)
            if let gwt = makeGameWithTeams(game) {
                dateCache[dayStart, default: []].append(gwt)
            }
        }
        // Sort each day's games by date
        for (key, games) in dateCache {
            dateCache[key] = games.sorted { ($0.game.standardDate ?? .distantPast) < ($1.game.standardDate ?? .distantPast) }
        }
        gamesWithTeamsDateCache = dateCache

        withAnimation {
            sortedGames = limitedSorted
            sortedGamesWithTeams = sortedWithTeams
        }
    }
    
    func setFavorites() {
        favoriteGames = filteredGames?.filter({favorites.contains($0)})
        // Pre-compute favorites with team data
        favoriteGamesWithTeams = (favoriteGames ?? []).compactMap { makeGameWithTeams($0) }
    }
    
    func resolveGameWithTeams(_ game: Game) -> GameWithTeams? {
        return makeGameWithTeams(game)
    }

    // MARK: - Per-Date Helpers (used by DayPage)

    /// Returns all sport-preference-filtered games for a specific date.
    /// Unlike sortedGamesWithTeams, this does NOT apply time-of-day filtering,
    /// so morning games remain visible in the afternoon.
    func gamesWithTeams(for date: Date) -> [GameWithTeams] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)

        // Check date cache first (populated by sortByDate)
        if let cached = gamesWithTeamsDateCache[start] {
            return cached
        }

        // Cache miss — compute and store
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let userPrefGames = getGamesFromUserPreferences()
        let result = userPrefGames
            .filter { game in
                guard let gameDate = game.standardDate else { return false }
                return gameDate >= start && gameDate < end
            }
            .sorted { ($0.standardDate ?? .distantPast) < ($1.standardDate ?? .distantPast) }
            .compactMap { makeGameWithTeams($0) }
        gamesWithTeamsDateCache[start] = result
        return result
    }

    /// Returns favorite games with teams for a specific date.
    func favoriteGamesWithTeams(for date: Date) -> [GameWithTeams] {
        gamesWithTeams(for: date).filter { favorites.contains($0.game) }
    }

    /// Returns non-favorite games grouped by sport for a specific date.
    func otherGamesBySport(for date: Date) -> [SportType: [GameWithTeams]] {
        let nonFavorites = gamesWithTeams(for: date).filter { !favorites.contains($0.game) }
        var grouped: [SportType: [GameWithTeams]] = [:]
        for gwt in nonFavorites {
            guard let leagueString = gwt.game.idLeague,
                  let intLeague = Int(leagueString),
                  let league = Leagues(rawValue: intLeague) else { continue }
            let sport = SportType(league: league)
            grouped[sport, default: []].append(gwt)
        }
        return grouped
    }

    /// Returns the total number of games for a date across ALL sports (ignoring sport filter preferences).
    func totalGameCount(for date: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return (totalGames ?? []).filter { game in
            guard let gameDate = game.standardDate else { return false }
            return gameDate >= start && gameDate < end
        }.count
    }

    /// Returns games for a date that exist in totalGames but NOT in filteredGames, grouped by sport.
    /// These are the games hidden by sport filter preferences.
    func hiddenGamesBySport(for date: Date) -> [SportType: [GameWithTeams]] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [:] }

        let filteredIDs = Set((filteredGames ?? []).compactMap(\.idEvent))

        let hiddenGames = (totalGames ?? []).filter { game in
            guard let gameDate = game.standardDate else { return false }
            guard gameDate >= start && gameDate < end else { return false }
            // Exclude games already shown (in filteredGames)
            if let eventID = game.idEvent, filteredIDs.contains(eventID) { return false }
            return true
        }

        var grouped: [SportType: [GameWithTeams]] = [:]
        for game in hiddenGames {
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let league = Leagues(rawValue: intLeague) else { continue }
            let sport = SportType(league: league)
            if let gwt = makeGameWithTeams(game) {
                grouped[sport, default: []].append(gwt)
            }
        }
        return grouped
    }

    /// Pre-computed sport counts per date (avoids recomputing for every day chip).
    /// Keyed by "yyyy-MM-dd" string for fast lookup.
    var sportCountsByDate: [String: [SportType: Int]] = [:]

    /// Rebuilds the sport-counts-per-date cache from filteredGames.
    func rebuildSportCountsCache() {
        let calendar = Calendar.current
        var result: [String: [SportType: Int]] = [:]
        for game in filteredGames ?? [] {
            guard let gameDate = game.standardDate else { continue }
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let league = Leagues(rawValue: intLeague) else { continue }
            let sport = SportType(league: league)
            let key = Self.sportCountDateFormatter.string(from: calendar.startOfDay(for: gameDate))
            result[key, default: [:]][sport, default: 0] += 1
        }
        sportCountsByDate = result
    }

    private static let sportCountDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Returns game counts per sport for a specific date (used for density heatmap on day chips).
    func gameCountsBySport(for date: Date) -> [SportType: Int] {
        let key = Self.sportCountDateFormatter.string(from: Calendar.current.startOfDay(for: date))
        return sportCountsByDate[key] ?? [:]
    }

    /// Returns the set of dates that have sport-preference-filtered games.
    /// Uses getGamesFromUserPreferences() so past games within a day are included.
    func datesWithGames() -> Set<DateComponents> {
        let calendar = Calendar.current
        var dates = Set<DateComponents>()
        for game in filteredGames ?? [] {
            guard let gameDate = game.standardDate else { continue }
            let dc = calendar.dateComponents([.day, .month, .year], from: gameDate)
            dates.insert(dc)
        }
        return dates
    }

    // MARK: - Up Next Helpers (used by DayPage empty state)

    /// Returns the next date after `date` that has filtered games.
    func nextDateWithGames(after date: Date) -> Date? {
        let calendar = Calendar.current
        let dayEnd = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: date) ?? date)
        return (filteredGames ?? [])
            .compactMap(\.standardDate)
            .filter { $0 >= dayEnd }
            .min()
            .map { calendar.startOfDay(for: $0) }
    }

    /// Returns the next game involving any favorited team after `date`.
    func nextFavoriteGame(after date: Date, favorites: Favorites) -> GameWithTeams? {
        guard !favorites.teams.isEmpty else { return nil }
        let calendar = Calendar.current
        let dayEnd = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: date) ?? date)
        return (filteredGames ?? [])
            .filter { game in
                guard let gameDate = game.standardDate, gameDate >= dayEnd else { return false }
                return favorites.contains(game)
            }
            .min { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
            .flatMap { makeGameWithTeams($0) }
    }

    /// Returns a compact summary of filtered games on a date (sport + count), sorted by count descending.
    func gameSummary(for date: Date) -> [(sport: SportType, count: Int)] {
        let games = gamesWithTeams(for: date)
        var counts: [SportType: Int] = [:]
        for gwt in games {
            guard let leagueString = gwt.game.idLeague,
                  let intLeague = Int(leagueString),
                  let league = Leagues(rawValue: intLeague) else { continue }
            let sport = SportType(league: league)
            counts[sport, default: 0] += 1
        }
        return counts
            .map { (sport: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Returns live events for a specific sport regardless of user preferences
    func liveEventsForSport(_ sport: SportType) -> [Game] {
        let events: [Game]?
        switch sport {
        case .soccer:     events = currentLiveInfo?.soccer?.events
        case .basketball: events = currentLiveInfo?.nba?.events
        case .hockey:     events = currentLiveInfo?.nhl?.events
        case .mlb:        events = currentLiveInfo?.mlb?.events
        case .nfl:        events = currentLiveInfo?.nfl?.events
        case .golf:       events = currentLiveInfo?.golf?.events
        case .tennis:     events = currentLiveInfo?.tennis?.events
        case .racing:     events = currentLiveInfo?.racing?.events
        }
        return (events ?? []).filter { game in
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let _ = Leagues(rawValue: intLeague) else { return false }
            return true
        }
    }

    private func makeGameWithTeams(_ game: Game) -> GameWithTeams? {
        // Check cache first
        if let cached = gameWithTeamsCache[game.id] {
            return cached
        }
        let result: GameWithTeams?
        if game.isIndividualSport {
            result = GameWithTeams(game: game, homeTeam: nil, awayTeam: nil)
        } else {
            guard let (homeTeam, awayTeam) = getTeams(for: game) else { return nil }
            result = GameWithTeams(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
        }
        if let result {
            gameWithTeamsCache[result.id] = result
        }
        return result
    }

    func getTeams(for game: Game) -> (home: Team, away: Team)? {
        let strHomeTeam = game.strHomeTeam
        let strAwayTeam = game.strAwayTeam

        let idHomeTeam = game.idHomeTeam
        let idAwayTeam = game.idAwayTeam

        // Individual sports (golf/tennis) don't have team IDs — create synthetic teams
        guard let idHomeTeam else {
            let homeTeam = Team(idTeam: game.idEvent ?? strHomeTeam, strTeam: strHomeTeam, strTeamShort: nil, strAlternate: nil, strTeamBadge: game.strHomeTeamBadge)
            let awayTeam = Team(idTeam: idAwayTeam ?? game.idEvent ?? strAwayTeam, strTeam: strAwayTeam, strTeamShort: nil, strAlternate: nil, strTeamBadge: game.strAwayTeamBadge)
            return (homeTeam, awayTeam)
        }

        guard let idAwayTeam else {
            let homeTeam = Team(idTeam: idHomeTeam, strTeam: strHomeTeam, strTeamShort: nil, strAlternate: nil, strTeamBadge: game.strHomeTeamBadge)
            let awayTeam = Team(idTeam: game.idEvent ?? strAwayTeam, strTeam: strAwayTeam, strTeamShort: nil, strAlternate: nil, strTeamBadge: game.strAwayTeamBadge)
            return (homeTeam, awayTeam)
        }

        // OPTIMIZED: Use O(1) lookup caches first (single hash table access)
        // Validate ID-based matches by name to avoid ESPN ID ↔ TheSportsDB ID collisions

        // Try to find home team using optimized cache
        var foundHomeTeam: Team? = {
            if let byID = teamByID[idHomeTeam], byID.strTeam == strHomeTeam { return byID }
            if let byName = teamByName[strHomeTeam] { return byName }
            // Fallback to legacy lookup (rare)
            if let byID = Team.getTeamInfoFrom(teamDict: self.teamsDict, teamID: idHomeTeam), byID.strTeam == strHomeTeam { return byID }
            return Team.getTeamInfoFrom(teamDict: self.teamsDictName, teamName: strHomeTeam)
        }()

        // Final fallback: Create team from game data if not found
        if foundHomeTeam == nil {
            foundHomeTeam = Team(
                idTeam: idHomeTeam,
                strTeam: strHomeTeam,
                strTeamShort: nil,
                strAlternate: nil,
                strTeamBadge: game.strHomeTeamBadge
            )
        }

        // Try to find away team using optimized cache
        var foundAwayTeam: Team? = {
            if let byID = teamByID[idAwayTeam], byID.strTeam == strAwayTeam { return byID }
            if let byName = teamByName[strAwayTeam] { return byName }
            // Fallback to legacy lookup (rare)
            if let byID = Team.getTeamInfoFrom(teamDict: self.teamsDict, teamID: idAwayTeam), byID.strTeam == strAwayTeam { return byID }
            return Team.getTeamInfoFrom(teamDict: self.teamsDictName, teamName: strAwayTeam)
        }()

        // Final fallback: Create team from game data if not found
        if foundAwayTeam == nil {
            foundAwayTeam = Team(
                idTeam: idAwayTeam,
                strTeam: strAwayTeam,
                strTeamShort: nil,
                strAlternate: nil,
                strTeamBadge: game.strAwayTeamBadge
            )
        }

        guard let homeTeam = foundHomeTeam, let awayTeam = foundAwayTeam else {
            SentrySDK.capture(error: ModelErrors.unknownTeam(game))
            return nil
        }

        return (homeTeam, awayTeam)
    }

    func retry() {
        networkFetchTask = nil
        getInfo()
    }

    /// Ensures the WebSocket is connected only when there are live or upcoming games.
    /// Call on foreground resume and after schedule updates.
    func ensureWebSocketConnected() {
        if shouldWebSocketBeActive() {
            guard webSocketTask == nil else { return }
            wsReconnectAttempts = 0
            handleLiveWebsocket()
        } else {
            disconnectWebSocket()
        }
    }

    /// Returns true if there are live games or games starting within 2 hours.
    private func shouldWebSocketBeActive() -> Bool {
        // Always connect if we already have live events
        if !allLiveEvents.isEmpty { return true }

        let now = Date()
        let twoHoursFromNow = now.addingTimeInterval(2 * 60 * 60)
        let fourHoursAgo = now.addingTimeInterval(-4 * 60 * 60)

        // Check if any filtered game is live or starting soon
        for game in filteredGames ?? [] {
            if game.strStatus == "in" { return true }
            if let date = game.standardDate, date >= fourHoursAgo && date <= twoHoursFromNow {
                return true
            }
        }
        return false
    }

    /// Cleanly disconnects the WebSocket and cancels any pending reconnect.
    private func disconnectWebSocket() {
        restartTimer?.invalidate()
        restartTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
    
    func handleSearch(searchString: String?) {
        if let searchString, isValidSearchString(searchString: searchString) {
            filteredGames = filteredGames?
                .filter({ game in
                    if game.isIndividualSport {
                        return game.strHomeTeam.localizedCaseInsensitiveContains(searchString) ||
                            game.strAwayTeam.localizedCaseInsensitiveContains(searchString)
                    }
                    guard let (homeTeam, awayTeam) = getTeams(for: game) else { return false }
                    return (homeTeam.strTeamShort ?? "").localizedCaseInsensitiveContains(searchString) ||
                    (homeTeam.strTeam ?? "").localizedCaseInsensitiveContains(searchString) ||
                    (awayTeam.strTeamShort ?? "").localizedCaseInsensitiveContains(searchString) ||
                    (awayTeam.strTeam ?? "").localizedCaseInsensitiveContains(searchString)
                })
        }
    }
    func isValidSearchString(searchString: String) -> Bool {
        return !searchString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    func getInfo(backgroundRefresh: Bool = false) {
        // Guard against concurrent fetches — don't start a new one if already in progress
        guard networkFetchTask == nil else { return }
        // Only show loading spinner if we have no cached data to display
        if !backgroundRefresh {
            networkState = .loading
        }
        restartTimer?.invalidate()
        restartTimer = nil
        networkFetchTask = Task {
            await getData()
        }
    }
    
    func dumpCaches() throws {
        teamCache?.deleteAll()
        gameCache?.deleteAll()
        liveCache?.deleteAll()
        try gameCache?.saveToDisk(with: "games")
        try teamCache?.saveToDisk(with: "teams")
        try liveCache?.saveToDisk(with: "live")
        getInfo()
    }
}

extension GameViewModel: @preconcurrency URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        self.webSocketTask = nil
        // Only reconnect WebSocket — don't refetch all data
        reconnectWebSocketOnly()
    }
}
#if canImport(ActivityKit) && os(iOS)
extension GameViewModel {
    func configureDataForLiveActivity(game: Game, homeTeam: Team, awayTeam: Team) async throws -> (attributes: LiveSportActivityAttributes, contentState: LiveSportActivityAttributes.ContentState) {
        guard let homeTeamName = homeTeam.strTeamShort ?? homeTeam.strTeam,
              let awayTeamName = awayTeam.strTeamShort ?? awayTeam.strTeam else { throw ModelErrors.unknownTeam(game) }

        // Download and cache badge images independently (don't require both to succeed)
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal") {
            await withTaskGroup(of: Void.self) { group in
                for (teamName, team) in [(homeTeamName, homeTeam), (awayTeamName, awayTeam)] {
                    guard let badgeString = team.strTeamBadge,
                          let badgeURL = URL(string: badgeString.contains("thesportsdb.com") ? badgeString + "/tiny" : badgeString) else { continue }
                    group.addTask {
                        do {
                            let (data, _) = try await URLSession.shared.data(for: URLRequest(url: badgeURL, cachePolicy: .returnCacheDataElseLoad))
                            // Validate the data is actually an image before saving
                            guard UIImage(data: data) != nil else {
                                AppLogger.liveActivity.notice("Badge data for \(teamName) is not a valid image")
                                return
                            }
                            let fileURL = containerURL.appendingPathComponent(teamName)
                            try data.write(to: fileURL)
                        } catch {
                            AppLogger.liveActivity.notice("Badge download failed for \(teamName): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }

        let initialContentState = LiveSportActivityAttributes.ContentState(homeScore: Int(game.intHomeScore ?? "") ?? 0, awayScore: Int(game.intAwayScore ?? "") ?? 0, status: game.strStatus, progress: game.strProgress, lastPlay: nil)
        let activityAttributes = LiveSportActivityAttributes(homeTeam: homeTeamName, awayTeam: awayTeamName, eventID: game.idEvent ?? "")
        return (activityAttributes, initialContentState)
    }
    func requestActivity(game: Game, homeTeam: Team, awayTeam: Team) {
        Task { @MainActor in
            do {
                let (activityAttributes, initialContentState) = try await configureDataForLiveActivity(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                let activity: Activity<LiveSportActivityAttributes>
                activity = try Activity.request(attributes: activityAttributes, contentState: initialContentState, pushType: .token)

                if appStorage.debugMode {
                    AutoFollowLogger.shared.log("Live activity started, observing push token updates...", level: .success)
                }

                // Observe the token stream — the token may not be available immediately
                observePushTokenUpdates(for: activity)
            } catch {
                if appStorage.debugMode {
                    AutoFollowLogger.shared.log("Live activity request failed: \(error.localizedDescription)", level: .error)
                }
                AppLogger.liveActivity.error("Failed to request live activity: \(error.localizedDescription)")
            }
        }
    }

    /// Observes push token updates for a single Live Activity and registers with the server.
    /// The token may arrive asynchronously after Activity.request(), so we must use the stream.
    private func observePushTokenUpdates(for activity: Activity<LiveSportActivityAttributes>) {
        let eventID = activity.attributes.eventID
        let homeTeam = activity.attributes.homeTeam
        let awayTeam = activity.attributes.awayTeam
        let isDebug = appStorage.debugMode
        Task.detached {
            for await tokenData in activity.pushTokenUpdates {
                let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
                if isDebug {
                    await MainActor.run {
                        AutoFollowLogger.shared.log("Push token received for \(homeTeam) vs \(awayTeam): \(tokenString.prefix(12))...", level: .success)
                    }
                }
                AppLogger.liveActivity.info("Registering push token for event \(eventID) (\(homeTeam) vs \(awayTeam)): \(tokenString.prefix(12))...")
                do {
                    try await NetworkHandler.subscribeToLiveActivityUpdate(token: tokenString, eventID: eventID, homeTeam: homeTeam, awayTeam: awayTeam, debug: isDebug)
                    if isDebug {
                        await MainActor.run {
                            AutoFollowLogger.shared.log("Server registered activity token OK (\(homeTeam) vs \(awayTeam))", level: .success)
                        }
                    }
                } catch {
                    AppLogger.liveActivity.error("Failed to register activity token: \(error.localizedDescription)")
                    if isDebug {
                        await MainActor.run {
                            AutoFollowLogger.shared.log("Failed to register activity token: \(error.localizedDescription)", level: .error)
                        }
                    }
                }
            }
        }
    }

    /// Re-registers push tokens for any already-running Live Activities (e.g. after app relaunch).
    func observeLiveActivities() {
        for activity in Activity<LiveSportActivityAttributes>.activities {
            AppLogger.liveActivity.info("Re-observing existing activity for event \(activity.attributes.eventID)")
            observePushTokenUpdates(for: activity)
        }
    }
    
    /// Registers for push-to-start Live Activity tokens and sends them to the server
    /// along with the user's favorite teams and auto-followed event IDs.
    func registerPushToStartIfNeeded() {
        let hasFavorites = appStorage.autoFollowFavorites && !favorites.teams.isEmpty
        let hasAutoFollows = !appStorage.autoFollowEventIDs.isEmpty
        guard hasFavorites || hasAutoFollows else { return }

        if appStorage.debugMode {
            AutoFollowLogger.shared.log("Registering push-to-start (favorites: \(favorites.teams.count), events: \(appStorage.autoFollowEventIDs.count))")
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task { @MainActor in
            for await token in Activity<LiveSportActivityAttributes>.pushToStartTokenUpdates {
                let tokenString = token.map { String(format: "%02x", $0) }.joined()
                self.currentPushToStartToken = tokenString
                if appStorage.debugMode {
                    AutoFollowLogger.shared.log("Got push-to-start token: \(tokenString.prefix(12))...", level: .success)
                }
                let favoritesList = appStorage.autoFollowFavorites ? Array(favorites.teams) : []
                let eventIDs = Array(appStorage.autoFollowEventIDs)
                do {
                    try await NetworkHandler.registerPushToStart(token: tokenString, favorites: favoritesList, eventIDs: eventIDs, debug: self.appStorage.debugMode)
                    if appStorage.debugMode {
                        AutoFollowLogger.shared.log("Server registered push-to-start OK", level: .success)
                    }
                    AppLogger.liveActivity.info("Registered push-to-start token with \(favoritesList.count) favorites, \(eventIDs.count) auto-follow events")
                } catch {
                    if appStorage.debugMode {
                        AutoFollowLogger.shared.log("Server registration failed: \(error.localizedDescription)", level: .error)
                    }
                    AppLogger.liveActivity.error("Failed to register push-to-start: \(error.localizedDescription)")
                }
            }
        }

        // Re-register when favorites change
        NotificationCenter.default.addObserver(forName: .favoritesDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sendPushToStartRegistration()
            }
        }
    }

    /// Sends the current push-to-start token, favorites, and auto-follow event IDs to the server.
    private func sendPushToStartRegistration() {
        let hasFavorites = appStorage.autoFollowFavorites && !favorites.teams.isEmpty
        let hasAutoFollows = !appStorage.autoFollowEventIDs.isEmpty
        guard hasFavorites || hasAutoFollows else { return }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Use cached token for immediate re-registration (don't wait for token update)
        if let cachedToken = currentPushToStartToken {
            Task { @MainActor in
                let favoritesList = appStorage.autoFollowFavorites ? Array(favorites.teams) : []
                let eventIDs = Array(appStorage.autoFollowEventIDs)
                try? await NetworkHandler.registerPushToStart(token: cachedToken, favorites: favoritesList, eventIDs: eventIDs, debug: self.appStorage.debugMode)
                if appStorage.debugMode {
                    AutoFollowLogger.shared.log("Re-registered push-to-start with \(favoritesList.count) favorites, \(eventIDs.count) events", level: .success)
                }
                AppLogger.liveActivity.info("Re-registered push-to-start with \(favoritesList.count) favorites, \(eventIDs.count) auto-follow events")
            }
        } else {
            // Fallback: wait for next token update
            Task { @MainActor in
                for await token in Activity<LiveSportActivityAttributes>.pushToStartTokenUpdates {
                    let tokenString = token.map { String(format: "%02x", $0) }.joined()
                    self.currentPushToStartToken = tokenString
                    let favoritesList = appStorage.autoFollowFavorites ? Array(favorites.teams) : []
                    let eventIDs = Array(appStorage.autoFollowEventIDs)
                    try? await NetworkHandler.registerPushToStart(token: tokenString, favorites: favoritesList, eventIDs: eventIDs, debug: self.appStorage.debugMode)
                    AppLogger.liveActivity.info("Re-registered push-to-start with \(favoritesList.count) favorites, \(eventIDs.count) auto-follow events")
                    break
                }
            }
        }
    }

    /// Called from AutoFollowButton when the user toggles auto-follow for a game.
    func sendAutoFollowRegistration() {
        if appStorage.debugMode {
            AutoFollowLogger.shared.log("Re-registering push-to-start (auto-follow changed)")
        }
        sendPushToStartRegistration()
    }

    /// Pre-caches badge images for specific teams to the app group container.
    func preCacheBadges(homeTeam: Team, awayTeam: Team) {
        Task {
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal") else { return }

            for team in [homeTeam, awayTeam] {
                guard let teamName = team.strTeamShort ?? team.strTeam else { continue }
                let fileURL = containerURL.appendingPathComponent(teamName)
                if FileManager.default.fileExists(atPath: fileURL.path) { continue }

                guard let badgeString = team.strTeamBadge,
                      let badgeURL = URL(string: badgeString.contains("thesportsdb.com") ? badgeString + "/tiny" : badgeString) else { continue }

                do {
                    let (data, _) = try await URLSession.shared.data(for: URLRequest(url: badgeURL, cachePolicy: .returnCacheDataElseLoad))
                    guard UIImage(data: data) != nil else { continue }
                    try data.write(to: fileURL)
                } catch {
                    AppLogger.liveActivity.notice("Failed to pre-cache badge for \(teamName): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Pre-caches badge images for all favorite teams to the app group container.
    func preCacheFavoriteTeamBadges() {
        guard !favorites.teams.isEmpty else { return }

        Task {
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal") else { return }

            for teamName in favorites.teams {
                let fileURL = containerURL.appendingPathComponent(teamName)
                if FileManager.default.fileExists(atPath: fileURL.path) { continue }

                guard let team = teamByName[teamName],
                      let badgeString = team.strTeamBadge,
                      let badgeURL = URL(string: badgeString.contains("thesportsdb.com") ? badgeString + "/tiny" : badgeString) else { continue }

                do {
                    let (data, _) = try await URLSession.shared.data(for: URLRequest(url: badgeURL, cachePolicy: .returnCacheDataElseLoad))
                    guard UIImage(data: data) != nil else { continue }
                    try data.write(to: fileURL)
                } catch {
                    AppLogger.liveActivity.notice("Failed to pre-cache badge for \(teamName): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Client-side fallback: auto-start Live Activity for auto-followed games that go live
    func checkAutoFollowedGamesForLiveStart() {
        let autoFollowIDs = appStorage.autoFollowEventIDs
        guard !autoFollowIDs.isEmpty else { return }

        var allLive = liveEvents
        if appStorage.debugMode {
            allLive += debugFakeGames.filter { $0.strStatus == "in" }
            AutoFollowLogger.shared.log("Checking \(autoFollowIDs.count) auto-follow IDs against \(allLive.count) live events")
        }

        for game in allLive {
            guard let eventID = game.idEvent,
                  autoFollowIDs.contains(eventID),
                  game.strStatus == "in" else { continue }

            // Don't start if already following
            if Activity<LiveSportActivityAttributes>.activities.contains(where: { $0.attributes.eventID == eventID }) {
                continue
            }

            guard let (homeTeam, awayTeam) = getTeams(for: game) else { continue }
            if appStorage.debugMode {
                AutoFollowLogger.shared.log("Auto-starting live activity for \(eventID) (\(game.strHomeTeam) vs \(game.strAwayTeam))", level: .success)
            }
            requestActivity(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
            appStorage.removeAutoFollow(eventID)
            AppLogger.liveActivity.info("Auto-started Live Activity for auto-followed event \(eventID)")
        }
    }

    func updateLiveActivities() async throws {
        // Build lookup by team names since event IDs may differ between schedule (TheSportsDB) and live data (ESPN)
        var statesByTeams: [String: LiveSportActivityAttributes.ContentState] = [:]
        var statesByEventID: [String: LiveSportActivityAttributes.ContentState] = [:]
        for liveEvent in allLiveEvents {
            let contentState = LiveSportActivityAttributes.ContentState(homeScore: Int(liveEvent.intHomeScore ?? "") ?? 0, awayScore: Int(liveEvent.intAwayScore ?? "") ?? 0, status: liveEvent.strStatus, progress: liveEvent.strProgress, lastPlay: nil)
            if let eventID = liveEvent.idEvent {
                statesByEventID[eventID] = contentState
            }
            // Key by lowercased team names for fuzzy matching
            let teamKey = "\(liveEvent.strHomeTeam.lowercased())|\(liveEvent.strAwayTeam.lowercased())"
            statesByTeams[teamKey] = contentState
        }
        for activity in Activity<LiveSportActivityAttributes>.activities {
            let currentState = activity.contentState
            let eventID = activity.attributes.eventID
            // Try event ID first, fall back to team name matching
            let newState = statesByEventID[eventID] ?? {
                let teamKey = "\(activity.attributes.homeTeam.lowercased())|\(activity.attributes.awayTeam.lowercased())"
                return statesByTeams[teamKey]
            }()
            if let newState, newState != currentState {
                await activity.update(using: newState)
            }
        }
    }
}
#endif

// MARK: - Debug Fake Game Injection
extension GameViewModel {
    /// Static storage for debug fake games.
    nonisolated(unsafe) private static var _debugFakeGames: [Game] = []

    /// Holds injected fake games for testing.
    var debugFakeGames: [Game] {
        get { Self._debugFakeGames }
        set { Self._debugFakeGames = newValue }
    }

    /// Injects a fake upcoming game and returns it.
    @discardableResult
    func injectFakeUpcomingGame(sport: SportType = .basketball) -> Game {
        let game = DebugGameFactory.createFakeUpcomingGame(sport: sport, secondsFromNow: 300)
        Self._debugFakeGames.append(game)

        // Register synthetic teams so getTeams(for:) works
        let (home, away) = DebugGameFactory.fakeTeams(for: game)
        if let id = home.idTeam { teamByID[id] = home }
        if let name = home.strTeam { teamByName[name] = home }
        if let id = away.idTeam { teamByID[id] = away }
        if let name = away.strTeam { teamByName[name] = away }

        // Merge into totalGames so it appears in the list
        if totalGames != nil {
            totalGames?.append(game)
        } else {
            totalGames = [game]
        }
        filterSports(force: true)

        AutoFollowLogger.shared.log("Created fake game: \(game.idEvent ?? "?") (\(game.strHomeTeam) vs \(game.strAwayTeam))", level: .info)
        return game
    }

    /// Transitions a fake game to live status and triggers auto-follow check.
    func transitionFakeGameToLive(eventID: String) {
        guard let index = Self._debugFakeGames.firstIndex(where: { $0.idEvent == eventID }) else { return }
        let liveGame = DebugGameFactory.transitionToLive(Self._debugFakeGames[index])
        Self._debugFakeGames[index] = liveGame

        // Update in totalGames too
        if let totalIndex = totalGames?.firstIndex(where: { $0.idEvent == eventID }) {
            totalGames?[totalIndex] = liveGame
        }
        filterSports(force: true)

        AutoFollowLogger.shared.log("Fake game \(eventID) transitioned to LIVE", level: .success)

        // Trigger auto-follow check
        #if canImport(ActivityKit) && os(iOS)
        checkAutoFollowedGamesForLiveStart()
        #endif
    }

    /// Schedules auto-transition to live after a delay.
    func scheduleAutoTransitionToLive(eventID: String, delay: TimeInterval) {
        AutoFollowLogger.shared.log("Scheduling auto-transition for \(eventID) in \(Int(delay))s")
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.transitionFakeGameToLive(eventID: eventID)
            }
        }
    }

    /// Removes all fake games and cleans up.
    func clearDebugFakeGames() {
        let fakeIDs = Set(Self._debugFakeGames.compactMap(\.idEvent))
        totalGames?.removeAll { game in
            guard let id = game.idEvent else { return false }
            return fakeIDs.contains(id)
        }
        // Remove auto-follow entries for fake games
        for id in fakeIDs {
            appStorage.removeAutoFollow(id)
        }
        Self._debugFakeGames.removeAll()
        filterSports(force: true)
        AutoFollowLogger.shared.log("Cleared all debug fake games", level: .info)
    }
}
