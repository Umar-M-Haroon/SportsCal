//
//  WatchViewModel.swift
//  SportsCalWatch
//
//  Manages data fetching via HTTP polling, local caching, and haptic score alerts.
//  No WebSocket — Watch suspends too aggressively for persistent connections.
//

import Foundation
import SwiftUI
import Combine
import SportsCalModel
import WatchKit

@Observable
final class WatchViewModel {
    var games: [Game] = []
    var liveGames: [Game] = []
    var teams: [Team] = []
    var isLoading = false
    /// When the data on screen was last fetched successfully (possibly in a previous launch).
    var lastUpdated: Date?
    /// The most recent schedule or live fetch failed; the last good data is still shown.
    var lastFetchFailed = false

    // Preferences synced from iPhone via WatchConnectivity
    var enabledSports: Set<SportType> = Set(SportType.allCases)
    var favoriteTeams: Set<String> = []
    var hiddenCompetitions: Set<String> = []

    // Polling
    private var previousScores: [String: (home: String, away: String)] = [:]
    private var consecutiveFailures = 0
    private var didInitialLoad = false
    private var scheduleTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var lastScheduleAttempt: Date?
    private var lastLiveAttempt: Date?

    var hasLiveGames: Bool { !liveGames.isEmpty }

    /// The data on screen is older than `WatchGameLogic.staleAfter`.
    var isStale: Bool {
        guard let lastUpdated else { return false }
        return Date().timeIntervalSince(lastUpdated) > WatchGameLogic.staleAfter
    }

    /// Seconds until the next foreground poll (see `WatchGameLogic.pollInterval`).
    var pollInterval: TimeInterval {
        WatchGameLogic.pollInterval(hasLiveGames: hasLiveGames, consecutiveFailures: consecutiveFailures)
    }

    // MARK: - Filtered Views

    var todayGames: [Game] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        return games.filter { game in
            guard let date = game.standardDate else { return false }
            return date >= today && date < tomorrow
        }
    }

    var favoriteGames: [Game] {
        games.filter { isFavorite($0) }
            .sorted { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
    }

    func isFavorite(_ game: Game) -> Bool {
        favoriteTeams.contains(game.strHomeTeam) || favoriteTeams.contains(game.strAwayTeam)
    }

    private func isFavoritesOnly(_ sport: SportType) -> Bool {
        let defaults = UserDefaults.standard
        switch sport {
        case .basketball: return defaults.bool(forKey: "favoritesOnlyNBA")
        case .soccer:     return defaults.bool(forKey: "favoritesOnlySoccer")
        case .hockey:     return defaults.bool(forKey: "favoritesOnlyNHL")
        case .mlb:        return defaults.bool(forKey: "favoritesOnlyMLB")
        case .nfl:        return defaults.bool(forKey: "favoritesOnlyNFL")
        case .golf:       return defaults.bool(forKey: "favoritesOnlyGolf")
        case .tennis:     return defaults.bool(forKey: "favoritesOnlyTennis")
        case .racing:     return defaults.bool(forKey: "favoritesOnlyRacing")
        }
    }

    /// Per-sport favorites-only plus tennis/golf event coverage (followed players always pass).
    func applyPerSportFavoritesFilter(_ games: [Game]) -> [Game] {
        let football = FootballPreference(defaults: .standard)
        return games.filter { game in
            guard let sport = game.sportType else { return true }
            let favorite = isFavorite(game)
            if isFavoritesOnly(sport) && !favorite { return false }
            // NFL / college switches, and college's Top 25 / conference coverage.
            if sport == .nfl { return football.admits(game) { favorite } }
            return game.passesCoverage(EventCoverage.stored(for: sport, in: .standard), isFavorite: favorite)
        }
    }

    func isLiveGame(_ game: Game) -> Bool {
        WatchGameLogic.isLive(game)
    }

    /// Sport toggles, hidden competitions, then per-sport favorites-only / coverage.
    func filterForDisplay(_ games: [Game]) -> [Game] {
        let visible = WatchGameLogic.visibleGames(
            games, enabledSports: enabledSports, hiddenCompetitions: hiddenCompetitions
        )
        return applyPerSportFavoritesFilter(visible)
    }

    // MARK: - Data Loading

    /// Called each time the scene becomes active. The first call loads preferences and the
    /// cache before fetching; later calls refresh (throttled), so launch fetches once.
    func becameActive() async {
        if !didInitialLoad {
            didInitialLoad = true
            await initialLoad()
        } else {
            await refreshOnWake()
        }
    }

    func initialLoad() async {
        loadPreferencesFromLocal()
        loadCachedData()
        await fetchSchedule()
    }

    func refreshOnWake() async {
        if hasLiveGames {
            if let last = lastLiveAttempt, Date().timeIntervalSince(last) < 10 { return }
            await fetchLiveScores()
        } else {
            if let last = lastScheduleAttempt, Date().timeIntervalSince(last) < 30 { return }
            await fetchSchedule()
        }
    }

    func poll() async {
        if hasLiveGames {
            await fetchLiveScores()
        } else if shouldRefreshSchedule() {
            await fetchSchedule()
        }
    }

    private func shouldRefreshSchedule() -> Bool {
        guard let last = lastUpdated else { return true }
        // Retry sooner after a failure (the poll interval already backs off).
        return lastFetchFailed || Date().timeIntervalSince(last) > 300 // 5 minutes
    }

    /// Fetches the schedule. A call made while a fetch is in flight joins it rather than
    /// starting another; `force` (preferences changed) cancels it and starts over.
    func fetchSchedule(force: Bool = false) async {
        if let running = scheduleTask {
            if force {
                running.cancel()
            } else {
                await running.value
                return
            }
        }
        let task = Task { await performScheduleFetch() }
        scheduleTask = task
        await task.value
        if scheduleTask == task { scheduleTask = nil }
    }

    private func performScheduleFetch() async {
        let sportTypes = Array(enabledSports)
        guard !sportTypes.isEmpty else { return }
        lastScheduleAttempt = Date()
        isLoading = true
        defer { isLoading = false }

        do {
            let (fetchedGames, fetchedTeams) = try await NetworkHandler.getWidgetScheduleFor(
                sports: sportTypes,
                limit: 30,
                favorites: Array(favoriteTeams)
            )
            try Task.checkCancellation()

            let filteredGames = filterForDisplay(fetchedGames)
            games = filteredGames
            teams = fetchedTeams
            liveGames = filteredGames.filter { isLiveGame($0) }
            lastUpdated = Date()
            recordSuccess()
            cacheData(games: filteredGames, teams: fetchedTeams)
        } catch {
            recordFailure(error)
        }
    }

    func fetchLiveScores() async {
        if let running = liveTask {
            await running.value
            return
        }
        let task = Task { await performLiveFetch() }
        liveTask = task
        await task.value
        liveTask = nil
    }

    /// `/live` has no sport filter or delta form over HTTP (`frames=v2` is WebSocket-only),
    /// so this is still the full pruned snapshot; the savings come from polling it only
    /// while the app is active and a visible game is live, and backing off on failure.
    private func performLiveFetch() async {
        lastLiveAttempt = Date()
        do {
            let liveScore = try await NetworkHandler.getLiveSnapshot()
            let allLive = collectAllGames(from: liveScore)

            // Detect score changes for haptics
            for game in allLive {
                checkForScoreChange(game)
            }

            liveGames = filterForDisplay(allLive.filter { isLiveGame($0) })
            games = WatchGameLogic.mergeLive(allLive, into: games)
            lastUpdated = Date()
            recordSuccess()
        } catch {
            recordFailure(error)
        }
    }

    private func recordSuccess() {
        lastFetchFailed = false
        consecutiveFailures = 0
    }

    private func recordFailure(_ error: Error) {
        // A superseded (cancelled) fetch isn't a failure.
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        lastFetchFailed = true
        consecutiveFailures += 1
    }

    private func collectAllGames(from liveScore: LiveScore) -> [Game] {
        var all: [Game] = []
        if let nba = liveScore.nba { all.append(contentsOf: nba.events) }
        if let mlb = liveScore.mlb { all.append(contentsOf: mlb.events) }
        if let soccer = liveScore.soccer { all.append(contentsOf: soccer.events) }
        if let nfl = liveScore.nfl { all.append(contentsOf: nfl.events) }
        if let nhl = liveScore.nhl { all.append(contentsOf: nhl.events) }
        if let golf = liveScore.golf { all.append(contentsOf: golf.events) }
        if let tennis = liveScore.tennis { all.append(contentsOf: tennis.events) }
        if let racing = liveScore.racing { all.append(contentsOf: racing.events) }
        return all
    }

    // MARK: - Haptic Score Alerts

    private func checkForScoreChange(_ game: Game) {
        guard let eventID = game.idEvent,
              let homeScore = game.intHomeScore,
              let awayScore = game.intAwayScore,
              isFavorite(game) else { return }

        let key = eventID
        if let previous = previousScores[key] {
            if previous.home != homeScore || previous.away != awayScore {
                let sportType = game.sportType
                if sportType == .soccer || sportType == .hockey || sportType == .nfl {
                    WKInterfaceDevice.current().play(.notification)
                } else {
                    WKInterfaceDevice.current().play(.click)
                }
            }
        }
        previousScores[key] = (home: homeScore, away: awayScore)
    }

    // MARK: - Local Caching

    private static var cacheURL: URL? {
        try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("watch-cache.json")
    }

    private func cacheData(games: [Game], teams: [Team]) {
        guard let url = Self.cacheURL else { return }
        let snapshot = WatchCacheSnapshot(games: games, teams: teams, updatedAt: Date())
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadCachedData() {
        guard let url = Self.cacheURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WatchCacheSnapshot.self, from: data) else { return }

        // Always show the cache rather than a blank screen; `isStale` marks it as old.
        // Stale "live" games are surely over, so they don't drive the live tab or polling.
        let isFresh = Date().timeIntervalSince(snapshot.updatedAt) < WatchGameLogic.staleAfter
        let visible = filterForDisplay(snapshot.games)
        games = visible
        teams = snapshot.teams
        liveGames = isFresh ? visible.filter { isLiveGame($0) } : []
        lastUpdated = snapshot.updatedAt
    }

    // MARK: - Preferences

    func loadPreferencesFromLocal() {
        let defaults = UserDefaults.standard

        // Load sport prefs synced via WatchConnectivity
        var sports = Set<SportType>()
        if defaults.bool(forKey: "shouldShowNBA") { sports.insert(.basketball) }
        if defaults.bool(forKey: "shouldShowSoccer") { sports.insert(.soccer) }
        if defaults.bool(forKey: "shouldShowNHL") { sports.insert(.hockey) }
        if defaults.bool(forKey: "shouldShowMLB") { sports.insert(.mlb) }
        if FootballPreference(defaults: defaults).isOn { sports.insert(.nfl) }
        if defaults.bool(forKey: "shouldShowGolf") { sports.insert(.golf) }
        if defaults.bool(forKey: "shouldShowTennis") { sports.insert(.tennis) }
        if defaults.bool(forKey: "shouldShowRacing") { sports.insert(.racing) }

        if !sports.isEmpty {
            enabledSports = sports
        }

        // Load favorites
        if let favArray = defaults.stringArray(forKey: "Favorites") {
            favoriteTeams = Set(favArray)
        }

        // Load hidden competitions
        if let hidden = defaults.stringArray(forKey: "hiddenCompetitions") {
            hiddenCompetitions = Set(hidden)
        }
    }

    func toggleSport(_ sport: SportType, enabled: Bool) {
        if enabled {
            enabledSports.insert(sport)
        } else {
            enabledSports.remove(sport)
        }
        saveSportPrefs()
        Task { await fetchSchedule(force: true) }
    }

    func removeFavorite(_ team: String) {
        favoriteTeams.remove(team)
        let defaults = UserDefaults.standard
        defaults.set(Array(favoriteTeams), forKey: "Favorites")

        // Notify iPhone via WatchConnectivity
        WatchSyncService.shared.sendFavoritesUpdate(Array(favoriteTeams))
    }

    private func saveSportPrefs() {
        let defaults = UserDefaults.standard
        defaults.set(enabledSports.contains(.basketball), forKey: "shouldShowNBA")
        defaults.set(enabledSports.contains(.soccer), forKey: "shouldShowSoccer")
        defaults.set(enabledSports.contains(.hockey), forKey: "shouldShowNHL")
        defaults.set(enabledSports.contains(.mlb), forKey: "shouldShowMLB")
        // Football on the watch is one switch over two leagues: off clears both, on keeps
        // whichever the phone chose (a college-only fan stays college-only).
        if !enabledSports.contains(.nfl) {
            defaults.set(false, forKey: "shouldShowNFL")
            defaults.set(false, forKey: "shouldShowCFB")
        } else if !FootballPreference(defaults: defaults).isOn {
            defaults.set(true, forKey: "shouldShowNFL")
        }
        defaults.set(enabledSports.contains(.golf), forKey: "shouldShowGolf")
        defaults.set(enabledSports.contains(.tennis), forKey: "shouldShowTennis")
        defaults.set(enabledSports.contains(.racing), forKey: "shouldShowRacing")
    }
}

// MARK: - Cache Model

private struct WatchCacheSnapshot: Codable {
    let games: [Game]
    let teams: [Team]
    let updatedAt: Date
}
