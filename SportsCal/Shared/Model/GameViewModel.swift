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

// MARK: - GameWithTeams
// Pre-computed game with team data to avoid expensive lookups during rendering
public struct GameWithTeams: Identifiable {
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
    private var gameCache: Cache<String, LiveScore>?
    private var teamCache: Cache<String, [Team]>?
    private var liveCache: Cache<String, LiveScore>?
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

        // Batch-assign all 9 stored properties — SwiftUI coalesces into one update
        liveEvents = computedLiveEvents
        liveEventsWithTeams = computedLiveEventsWithTeams
        allLiveEvents = computedAllLiveEvents
        currentlyLiveSports = computedCurrentlyLiveSports
        liveGameCountsBySport = computedLiveGameCounts
        todayGames = computedTodayGames
        todayGamesWithTeams = computedTodayGamesWithTeams
        todayFavoriteGamesWithTeams = computedTodayFavorites
        todayOtherGamesBySport = computedTodayOther

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
            sports.append(.basketball)
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
                      let _ = Leagues(rawValue: intLeague) else { return false }
                return true
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
                      let _ = Leagues(rawValue: intLeague) else {
                    return true
                }
                return false
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
        
        if let cacheGames = gameCache?.value(for: "games") {
            setGames(result: cacheGames)
        }
        if let cacheTeams = teamCache?.value(for: "teams") {
            self.teams = cacheTeams
            buildTeamLookupCaches()
        }
//        if let liveInfo = liveCache?.value(for: "live") {
//            self.currentLiveInfo = liveInfo
//        }
        getInfo()
        
        // Note: With @Observable, changes to appStorage properties are automatically tracked
        // No need for manual observation like the old objectWillChange.sink pattern
    }
    
    private func handleLiveGames() async throws {
        AppLogger.networking.info("Getting live games")
        var liveInfo = try await NetworkHandler.getLiveSnapshot(debug: appStorage.debugMode)
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
        webSocketTask = NetworkHandler.connectWebSocketForLive(debug: appStorage.debugMode)
        webSocketTask?.resume()
        Task {
            try await receiveMessages()
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
            self?.webSocketTask = NetworkHandler.connectWebSocketForLive(debug: self?.appStorage.debugMode ?? false)
            self?.webSocketTask?.resume()
            Task { @MainActor [weak self] in
                try await self?.receiveMessages()
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
        setGames(result: groupResult)
    }
    
    @objc
    private func getData() async {
        // Each handler catches its own errors so a single failure doesn't trigger a full retry
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do { try await self.handleTeams() }
                catch { AppLogger.networking.error("handleTeams failed: \(error.localizedDescription)") }
            }
            group.addTask {
                do { try await self.handleLiveGames() }
                catch { AppLogger.networking.error("handleLiveGames failed: \(error.localizedDescription)") }
            }
            group.addTask {
                do { try await self.handleGames() }
                catch { AppLogger.networking.error("handleGames failed: \(error.localizedDescription)") }
            }
            await group.waitForAll()
        }
        handleLiveWebsocket()
        #if canImport(ActivityKit) && os(iOS)
        if #available(iOS 16.1, *) {
            registerPushToStartIfNeeded()
            preCacheFavoriteTeamBadges()
        }
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
                    if #available(iOS 16.1, *) {
                        Task { @MainActor in
                            try await updateLiveActivities()
                            checkAutoFollowedGamesForLiveStart()
                        }
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
    
    func setGames(result: LiveScore) {
        totalGames = [result.nhl?.events, result.nfl?.events, result.soccer?.events, result.mlb?.events, result.nba?.events, result.golf?.events, result.tennis?.events, result.racing?.events]
            .compactMap({$0})
            .flatMap({$0})
        filterSports(force: true)
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
            allGames.append(contentsOf: gamesDict[.soccer] ?? [])
            allGames = allGames.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return league.isSoccer && !appStorage.hiddenCompetitions.contains(where: {$0 == league.leagueName})
            }
        }
        if appStorage.shouldShowMLB {
            allGames.append(contentsOf: gamesDict[.mlb] ?? [])
        }
        if appStorage.shouldShowNBA {
            if let basketballGames = gamesDict[.basketball] {
                allGames.append(contentsOf: basketballGames)
            }
        }
        if appStorage.shouldShowNFL {
            allGames.append(contentsOf: gamesDict[.nfl] ?? [])
        }
        if appStorage.shouldShowNHL {
            allGames.append(contentsOf: gamesDict[.hockey] ?? [])
        }
        if appStorage.shouldShowGolf {
            allGames.append(contentsOf: gamesDict[.golf] ?? [])
        }
        if appStorage.shouldShowTennis {
            allGames.append(contentsOf: gamesDict[.tennis] ?? [])
        }
        if appStorage.shouldShowRacing {
            allGames.append(contentsOf: gamesDict[.racing] ?? [])
        }
        return allGames
    }
    
    func showGame(game: Game) -> Bool {
        // if hidePastEvents
        // if game in past
        guard let date = game.standardDate else { return false}
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
    
    func filterSports(searchString: String? = nil, force: Bool = false) {
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

        AppLogger.viewModel.info("Total games: \(self.totalGames?.count ?? 0), filtered: \(self.filteredGames?.count ?? 0)")
        handleSearch(searchString: searchString)
        sortByDate()
        setFavorites()
        updateLiveData()
    }
    func sortByDate() {
        let groupDic = Dictionary(grouping: filteredGames ?? []) { game -> DateComponents in
            let gameDate = game.standardDate ?? .now
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
        if game.isIndividualSport {
            return GameWithTeams(game: game, homeTeam: nil, awayTeam: nil)
        }
        guard let (homeTeam, awayTeam) = getTeams(for: game) else { return nil }
        return GameWithTeams(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
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
    func getInfo() {
        // Guard against concurrent fetches — don't start a new one if already in progress
        guard networkFetchTask == nil else { return }
        networkState = .loading
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

extension GameViewModel: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        self.webSocketTask = nil
        // Only reconnect WebSocket — don't refetch all data
        reconnectWebSocketOnly()
    }
}
#if canImport(ActivityKit) && os(iOS)
@available(iOS 16.1, *)
extension GameViewModel {
    func configureDataForLiveActivity(game: Game, homeTeam: Team, awayTeam: Team) async throws -> (attributes: LiveSportActivityAttributes, contentState: LiveSportActivityAttributes.ContentState) {
        guard let homeTeamName = homeTeam.strTeamShort ?? homeTeam.strTeam,
              let awayTeamName = awayTeam.strTeamShort ?? awayTeam.strTeam else { throw ModelErrors.unknownTeam(game) }

        // Download and cache badge images when available
        if let homeBadgeString = homeTeam.strTeamBadge,
           let homeBadgeURL = URL(string: homeBadgeString.contains("thesportsdb.com") ? homeBadgeString + "/tiny" : homeBadgeString),
           let awayBadgeString = awayTeam.strTeamBadge,
           let awayBadgeURL = URL(string: awayBadgeString.contains("thesportsdb.com") ? awayBadgeString + "/tiny" : awayBadgeString) {
            do {
                async let (homeData, _) = URLSession.shared.data(for: URLRequest(url: homeBadgeURL, cachePolicy: .returnCacheDataElseLoad))
                async let (awayData, _) = URLSession.shared.data(for: URLRequest(url: awayBadgeURL, cachePolicy: .returnCacheDataElseLoad))

                if let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appending(path: homeTeamName) {
                    try await homeData.write(to: fileURL)
                }

                if let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appending(path: awayTeamName) {
                    try await awayData.write(to: fileURL)
                }
            } catch {
                // Badge download failed — continue without badges (e.g. debug fake teams)
                AppLogger.liveActivity.notice("Badge download failed, continuing without images: \(error.localizedDescription)")
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
                    if let pushToken = activity.pushToken {
                        let tokenPrefix = pushToken.map { String(format: "%02x", $0) }.joined().prefix(12)
                        AutoFollowLogger.shared.log("Live activity started, push token: \(tokenPrefix)...", level: .success)
                    } else {
                        AutoFollowLogger.shared.log("Live activity started (no push token yet)", level: .success)
                    }
                }

                if let token = activity.pushToken, let eventID = game.idEvent {
                    let tokenString = token.map { String(format: "%02x", $0)}.joined()
                    try await NetworkHandler.subscribeToLiveActivityUpdate(token: tokenString, eventID: eventID, debug: appStorage.debugMode)
                }
            } catch {
                if appStorage.debugMode {
                    AutoFollowLogger.shared.log("Live activity request failed: \(error.localizedDescription)", level: .error)
                }
                AppLogger.liveActivity.error("Failed to request live activity: \(error.localizedDescription)")
            }
        }
    }
    
    func observeLiveActivities() {
        
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

        if #available(iOS 17.2, *) {
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
    }

    /// Sends the current push-to-start token, favorites, and auto-follow event IDs to the server.
    private func sendPushToStartRegistration() {
        let hasFavorites = appStorage.autoFollowFavorites && !favorites.teams.isEmpty
        let hasAutoFollows = !appStorage.autoFollowEventIDs.isEmpty
        guard hasFavorites || hasAutoFollows else { return }

        if #available(iOS 17.2, *) {
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
                let fileURL = containerURL.appending(path: teamName)
                if FileManager.default.fileExists(atPath: fileURL.path) { continue }

                guard let badgeString = team.strTeamBadge,
                      let badgeURL = URL(string: badgeString.contains("thesportsdb.com") ? badgeString + "/tiny" : badgeString) else { continue }

                do {
                    let (data, _) = try await URLSession.shared.data(for: URLRequest(url: badgeURL, cachePolicy: .returnCacheDataElseLoad))
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
                let fileURL = containerURL.appending(path: teamName)
                if FileManager.default.fileExists(atPath: fileURL.path) { continue }

                guard let team = teamByName[teamName],
                      let badgeString = team.strTeamBadge,
                      let badgeURL = URL(string: badgeString.contains("thesportsdb.com") ? badgeString + "/tiny" : badgeString) else { continue }

                do {
                    let (data, _) = try await URLSession.shared.data(for: URLRequest(url: badgeURL, cachePolicy: .returnCacheDataElseLoad))
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
        var states: [String: LiveSportActivityAttributes.ContentState] = [:]
        for liveEvent in liveEvents {
            if let eventID = liveEvent.idEvent {
                let contentState = LiveSportActivityAttributes.ContentState(homeScore: Int(liveEvent.intHomeScore ?? "") ?? 0, awayScore: Int(liveEvent.intAwayScore ?? "") ?? 0, status: liveEvent.strStatus, progress: liveEvent.strProgress, lastPlay: nil)
                states[eventID] = contentState
            }
        }
        for activity in Activity<LiveSportActivityAttributes>.activities {
            for await data in activity.pushTokenUpdates {
                let myToken = data.map { String(format: "%02x", $0)}.joined()
                try await NetworkHandler.subscribeToLiveActivityUpdate(token: myToken, eventID: activity.attributes.eventID, debug: appStorage.debugMode)
            }
            let currentState = activity.contentState
            let currentAttributes = activity.attributes
            let eventID = currentAttributes.eventID
            if let savedContentState = states[eventID], savedContentState != currentState {
                await activity.update(using: savedContentState)
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
        if #available(iOS 16.1, *) {
            checkAutoFollowedGamesForLiveStart()
        }
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
