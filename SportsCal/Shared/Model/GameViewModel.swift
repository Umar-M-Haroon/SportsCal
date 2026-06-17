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
import Network
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

    // MARK: - Disk-cache schema version
    /// Bump when Game, LiveScore, or any cached Codable shape changes so previously
    /// persisted `games.cache` / `teams.cache` / `live.cache` files are invalidated
    /// instead of out-voting freshly parsed responses.
    static let cacheSchemaVersion = 3

    /// Versioned base name for `Cache.saveToDisk(with:)` — no `.cache` suffix (it appends).
    /// `nonisolated` so background-task helpers (which run outside the main actor)
    /// can build cache paths without hopping actors.
    nonisolated static func cacheStem(base: String) -> String {
        "\(base)-v\(cacheSchemaVersion)"
    }

    /// Full filename including extension, used when reading directly or purging.
    nonisolated static func cacheFilename(base: String) -> String {
        "\(cacheStem(base: base)).cache"
    }

    /// Snapshot of bundled baseline assets used when no on-disk cache exists yet.
    /// Either side may be nil; callers handle each independently.
    struct BundledBaseline {
        let liveScore: LiveScore?
        let teams: [Team]?
    }

    /// Loads bundled baseline JSON resources, if present in the app bundle. Both
    /// `baseline-schedule.json` and `baseline-teams.json` are optional — first-launch
    /// experience improves whenever a release ships with these resources baked in.
    /// Generate fresh files at release-cut time via Scripts/refresh-baseline.sh.
    static func loadBundledBaselineSnapshot() -> BundledBaseline? {
        let bundle = Bundle.main
        var liveScore: LiveScore?
        var teams: [Team]?
        if let url = bundle.url(forResource: "baseline-schedule", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            liveScore = try? NetworkHandler.sharedDecoder.decode(LiveScore.self, from: data)
        }
        if let url = bundle.url(forResource: "baseline-teams", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            teams = try? NetworkHandler.sharedDecoder.decode([Team].self, from: data)
        }
        if liveScore == nil && teams == nil { return nil }
        return BundledBaseline(liveScore: liveScore, teams: teams)
    }

    /// Background-task-safe schedule + teams refresh. Hits the same endpoints the
    /// foreground path uses, persists fresh `LiveScore` and `[Team]` snapshots to
    /// the on-disk caches, and never touches `@Observable` state — so it's safe to
    /// invoke from a `.backgroundTask(.appRefresh:)` handler where no view-model
    /// instance is alive.
    ///
    /// On the next foreground launch, `init` reads these files at line ~556 and the
    /// user sees today's schedule on the first frame, even after the app sat closed
    /// for hours or days.
    nonisolated static func refreshCachesInBackground() async {
        do {
            async let scheduleTask = NetworkHandler.handleCall()
            async let teamsTask = NetworkHandler.getTeams()
            let (snapshot, fetchedTeams) = try await (scheduleTask, teamsTask)

            let games = Cache<String, LiveScore>()
            games.insert(snapshot, for: "games")
            try games.saveToDisk(with: cacheStem(base: "games"))

            let teams = Cache<String, [Team]>()
            teams.insert(fetchedTeams, for: "teams")
            try teams.saveToDisk(with: cacheStem(base: "teams"))

            AppLogger.networking.info("Background refresh: persisted \(fetchedTeams.count) teams + schedule snapshot")
        } catch {
            AppLogger.networking.error("Background refresh failed: \(error.localizedDescription)")
        }
    }

    static func purgeLegacyCacheFiles() {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let currentFilenames: Set<String> = ["games", "teams", "live"]
            .map { cacheFilename(base: $0) }
            .reduce(into: []) { $0.insert($1) }
        if let contents = try? fm.contentsOfDirectory(atPath: dir.path) {
            for name in contents where name.hasSuffix(".cache") && !currentFilenames.contains(name) {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    /// Test hook: when true, skip network fetches and websocket setup at init.
    /// Used by snapshot tests to keep fixture data intact.
    static var isSnapshotTesting: Bool = false

    var appStorage: UserDefaultStorage
    var engagementTracker: EngagementTracker?
    var totalGames: [Game]?
    var filteredGames: [Game]?
    /// Backing cache for `calendarGames`. Invalidated (set nil) at the single
    /// `filterSports` chokepoint whenever the calendar source set can change.
    @ObservationIgnored private var _calendarGamesCache: [Game]?
    /// All games for the Calendar/Browse tabs (every sport, minus hidden soccer
    /// competitions), sorted by date. Built lazily on first access and memoized:
    /// the Calendar tab is usually not on screen at launch, so eagerly sorting
    /// ~45k games on every `filterSports` was pure waste (a dominant -Onone launch
    /// cost). Reading `totalGames` / `hiddenCompetitions` here keeps SwiftUI
    /// observation wired so the calendar repaints when the source actually changes.
    var calendarGames: [Game]? {
        guard let total = totalGames else { return nil }
        if let cached = _calendarGamesCache { return cached }
        let built = total.filter { game in
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let league = Leagues(rawValue: intLeague), league.isSoccer else { return true }
            return !appStorage.hiddenCompetitions.contains(league.leagueName)
        }.sorted { ($0.standardDate ?? .now) < ($1.standardDate ?? .now) }
        _calendarGamesCache = built
        return built
    }
    var teamString: String? = ""
    var favoriteGames: [Game]?
    var favoriteGamesWithTeams: [GameWithTeams] = []
    var sortedGames: Array<(key: DateComponents, value: Array<Game>)> = []
    var sortedGamesWithTeams: [GameDateSection] = []
    var networkState: NetworkState = .loading
    /// True while the device has no network path. Drives the offline banner / empty-state.
    var isOffline: Bool = false
    /// Timestamp of the last fully-successful fetch, for the "showing data from …" label.
    var lastSuccessfulFetch: Date?
    /// True when we're showing cached data because the live feed is unreachable:
    /// we have games AND we're either offline or the last fetch failed.
    var showsStaleBanner: Bool {
        (isOffline || networkState == .failed) && (totalGames?.isEmpty == false)
    }
    /// True when offline with no cached games — a full-screen placeholder reads
    /// better than an empty list.
    var showsOfflinePlaceholder: Bool {
        isOffline && (totalGames?.isEmpty ?? true)
    }
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
    var worldCup: WorldCupEnrichment?

    var favorites: Favorites
    var teams: [Team] = []
    var teamsDict: [String? : [Team]] = [:]
    var teamsDictName: [String? : [Team]] = [:]
    // Optimized O(1) lookup caches - maps team ID directly to Team (not array)
    var teamByID: [String: Team] = [:]
    var teamByName: [String: Team] = [:]
    var restartTimer: Timer?
    var gamesDict: [SportType: [Game]] = [:]
    
    var webSocketTask: URLSessionWebSocketTask?
    private var webSocketSession: URLSession?
    /// Developer "replay a game as live" is active. While true, the normal live-socket
    /// reconnect/ensure paths stand down so they don't clobber the replay stream.
    var isReplaying: Bool = false
    /// The game currently being replayed (used by the dev UI / Live Activity start).
    var replayingGame: Game?

    // MARK: Replay status (developer UI)
    enum ReplayPhase: String {
        case fetching = "Fetching plays…"
        case streaming = "Streaming"
        case ended = "Ended"
        case failed = "Failed"
    }
    /// Where the replay's play-by-play was sourced from ("Local server" / "Production").
    enum ReplaySource: String { case localServer = "Local server", production = "Production" }
    var replayPhase: ReplayPhase?
    var replaySource: ReplaySource?
    var replayTotalPlays: Int = 0
    var replayFramesReceived: Int = 0
    /// Coalesces `updateLiveData()` invocations arriving within ~250 ms of each other.
    /// During busy live windows several sports can each push within a few hundred ms,
    /// and `updateLiveData()` does ~10 array recompositions per call; batching them
    /// keeps the main thread free for scroll.
    private var pendingLiveUpdate: Task<Void, Never>?
    private var gameCache: Cache<String, LiveScore>?
    private var teamCache: Cache<String, [Team]>?
    private var liveCache: Cache<String, LiveScore>?
    /// Cache for makeGameWithTeams() results, keyed by game ID
    private var gameWithTeamsCache: [String: GameWithTeams] = [:]
    /// Compound key for `gamesWithTeamsDateCache` so cached entries built under one
    /// filter state survive when the user toggles to another and back. Filter-only
    /// changes used to wipe every visible day's cached `[GameWithTeams]`.
    private struct DateCacheKey: Hashable {
        let date: Date
        let filterHash: Int
    }
    /// Cache for gamesWithTeams(for:) results, keyed by (day, filterHash).
    private var gamesWithTeamsDateCache: [DateCacheKey: [GameWithTeams]] = [:]
    /// Snapshot of the current filter state's hash. Recomputed at each filterSports()
    /// call; reads/writes against the date cache use this to scope entries.
    private var currentFilterStateHash: Int = 0
    /// Whether a network fetch is currently in progress (visible to views for loading state).
    var isFetching: Bool { networkFetchTask != nil }
    private var networkFetchTask: Task<Void, Never>?
    var wsReconnectAttempts = 0
    /// Set when the last WS failure was a fatal oversized-frame error. Reconnecting
    /// can't fix it, so the reconnect path falls back to a slow REST live refresh
    /// instead of hammering the normal 2–60s backoff curve. Cleared on any clean
    /// receive / forced reconnect.
    @ObservationIgnored private var wsFatalFrameError = false
    /// Tracks current network reachability so the WebSocket reconnect loop can pause
    /// while offline and resume immediately when the path comes back, instead of
    /// burning attempts against an unreachable host.
    nonisolated(unsafe) private var pathMonitor: NWPathMonitor?
    var hasNetworkPath: Bool = true
    
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

    /// Debounced wrapper around `updateLiveData()`. A 250 ms window is short enough
    /// that score updates still feel responsive (the next server tick lands well
    /// within human reaction time) but long enough to collapse the 3–4 messages/sec
    /// burst seen during multi-sport live windows.
    private func scheduleLiveDataUpdate() {
        pendingLiveUpdate?.cancel()
        pendingLiveUpdate = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.updateLiveData()
        }
    }

    /// Whether a soccer game's league passes the sport-enable gate. Soccer is
    /// admitted when the user has enabled all of Soccer, OR when they've opted into
    /// the World Cup specifically and this is the World Cup league.
    func soccerGamePassesEnableGate(_ league: Leagues) -> Bool {
        if appStorage.shouldShowSoccer { return true }
        if appStorage.shouldShowWorldCup && league == .FIFA_World_Cup { return true }
        return false
    }

    private func computeCurrentlyLiveSports() -> [SportType] {
        var sports: [SportType] = []
        if (appStorage.shouldShowSoccer || appStorage.shouldShowWorldCup), let events = currentLiveInfo?.soccer?.events, !events.isEmpty {
            let filtered = events.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return league.isSoccer && soccerGamePassesEnableGate(league) && !appStorage.hiddenCompetitions.contains(where: {$0 == league.leagueName})
            }
            if !filtered.isEmpty { sports.append(.soccer) }
        }
        if appStorage.shouldShowMLB, let events = currentLiveInfo?.mlb?.events, !events.isEmpty {
            sports.append(.mlb)
        }
        if (appStorage.shouldShowNBA || appStorage.shouldShowWNBA), let events = currentLiveInfo?.nba?.events, !events.isEmpty {
            let filtered = events.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                if !league.isBasketball || appStorage.hiddenCompetitions.contains(league.leagueName) { return false }
                return league == .wnba ? appStorage.shouldShowWNBA : appStorage.shouldShowNBA
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
                return league.isSoccer && soccerGamePassesEnableGate(league) && !appStorage.hiddenCompetitions.contains(where: {$0 == league.leagueName})
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
        if appStorage.shouldShowSoccer || appStorage.shouldShowWorldCup {
            var soccerGames = currentLiveInfo?.soccer?.events
            soccerGames = soccerGames?.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return league.isSoccer && soccerGamePassesEnableGate(league) && !appStorage.hiddenCompetitions.contains(where: {$0 == league.leagueName})
            }
            if let soccerGames {
                games.append(contentsOf: applyFavoritesFilter(soccerGames, favoritesOnly: appStorage.favoritesOnlySoccer))
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
                games.append(contentsOf: applyFavoritesFilter(baseballGames, favoritesOnly: appStorage.favoritesOnlyMLB))
            }
        }
        if appStorage.shouldShowNBA || appStorage.shouldShowWNBA {
            var basketballGames = currentLiveInfo?.nba?.events
            basketballGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else {
                    return true
                }
                if !league.isBasketball || appStorage.hiddenCompetitions.contains(league.leagueName) { return true }
                return league == .wnba ? !appStorage.shouldShowWNBA : !appStorage.shouldShowNBA
            })
            if let basketballGames {
                games.append(contentsOf: applyFavoritesFilter(basketballGames, favoritesOnly: appStorage.favoritesOnlyNBA))
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
                games.append(contentsOf: applyFavoritesFilter(nflGames, favoritesOnly: appStorage.favoritesOnlyNFL))
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
                games.append(contentsOf: applyFavoritesFilter(nhlGames, favoritesOnly: appStorage.favoritesOnlyNHL))
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
                games.append(contentsOf: applyFavoritesFilter(golfGames, favoritesOnly: appStorage.favoritesOnlyGolf))
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
                games.append(contentsOf: applyFavoritesFilter(tennisGames, favoritesOnly: appStorage.favoritesOnlyTennis))
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
                games.append(contentsOf: applyFavoritesFilter(racingGames, favoritesOnly: appStorage.favoritesOnlyRacing))
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
        
        // Delete any cache files from prior schema versions so a stale on-disk copy
        // can never out-vote a fresh fetch. Bump Self.cacheSchemaVersion whenever
        // Game/LiveScore gains or changes fields.
        Self.purgeLegacyCacheFiles()

        let folderURLs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        do {
            guard let cacheFolder = folderURLs.first else {
                throw CocoaError(.fileNoSuchFile)
            }
            let gameFileURL = cacheFolder.appendingPathComponent(Self.cacheFilename(base: "games"))
            let teamFileURL = cacheFolder.appendingPathComponent(Self.cacheFilename(base: "teams"))
            let data = try NetworkHandler.sharedDecoder.decode(Cache<String, LiveScore>.self, from: Data(contentsOf: gameFileURL))
            self.gameCache = data
            let teamData = try NetworkHandler.sharedDecoder.decode(Cache<String, [Team]>.self, from: Data(contentsOf: teamFileURL))
            self.teamCache = teamData
        } catch let error {
            self.gameCache = Cache<String, LiveScore>()
            self.teamCache = Cache<String, [Team]>()
            self.liveCache = Cache<String, LiveScore>(entryLifetime: 15 * 60)
            AppLogger.viewModel.error("Cache load failed: \(error.localizedDescription)")
        }

        // Call super.init() after all stored properties are initialized
        super.init()

        if GameViewModel.isSnapshotTesting {
            self.networkState = .loaded
            return
        }

        self.webSocketSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

        var hasCachedData = false
        // Load cached teams *before* cached games. setGames() runs a full
        // filterSports pass (snapshot write + Spotlight index + 45k filter/sort);
        // doing it before teams exist produced a wasted teams-less first pass
        // (log: "Teams loaded: 0 … wrote 9210 bytes (0 teams)") that immediately
        // re-ran once teams arrived. Teams-first makes that first pass correct.
        if let cacheTeams = teamCache?.value(for: "teams") {
            self.teams = cacheTeams
            buildTeamLookupCaches()
        }
        if let cacheGames = gameCache?.value(for: "games") {
            setGames(result: cacheGames)
            hasCachedData = true
        }
        // First-launch fallback: if no disk cache exists yet, fall through to a
        // bundled baseline snapshot so the very first app open still shows games
        // instead of a spinner. Stale-by-design — getInfo() refreshes within seconds.
        if !hasCachedData, let bundled = Self.loadBundledBaselineSnapshot() {
            if let teams = bundled.teams, !teams.isEmpty {
                self.teams = teams
                buildTeamLookupCaches()
            }
            if let liveScore = bundled.liveScore {
                setGames(result: liveScore)
                hasCachedData = true
            }
        }
        // If we loaded cached games, show them immediately instead of a loading spinner
        if hasCachedData {
            self.networkState = .loaded
        }
        getInfo(backgroundRefresh: hasCachedData)
        observeServerEnvironmentChanges()
        startPathMonitor()

        // Note: With @Observable, changes to appStorage properties are automatically tracked
        // No need for manual observation like the old objectWillChange.sink pattern
    }

    deinit {
        pathMonitor?.cancel()
    }

    /// Watches network reachability so the WebSocket reconnect loop can wait while
    /// offline and force-reconnect the moment the path is restored.
    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(satisfied: satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.sportscal.pathmonitor"))
        self.pathMonitor = monitor
    }

    /// Applies a network-path change: tracks offline state and, on restore,
    /// resets the backoff and forces an immediate WebSocket reconnect.
    @MainActor
    func handlePathUpdate(satisfied: Bool) {
        let wasOffline = !hasNetworkPath
        hasNetworkPath = satisfied
        isOffline = !satisfied
        if satisfied && wasOffline {
            if appStorage.debugMode {
                AppLogger.networking.info("Network path restored — forcing WebSocket reconnect")
            }
            wsReconnectAttempts = 0
            restartTimer?.invalidate()
            restartTimer = nil
            ensureWebSocketConnected()
        }
    }

    /// Listens for `.serverEnvironmentDidChange` and, on a switch, drops
    /// live/schedule caches, reconnects the WebSocket, deregisters every
    /// push-to-start and Live Activity token against the **previous** host,
    /// and then re-registers against the new one.
    ///
    /// The deregister-before-register order is what stops duplicate Live
    /// Activities: without it, both servers' Redis instances retain the same
    /// install's registrations until TTL expiry, and each independently fires
    /// push-to-start when a favorited team next goes live.
    private func observeServerEnvironmentChanges() {
        NotificationCenter.default.addObserver(
            forName: .serverEnvironmentDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let previousBaseURL = notification.userInfo?["previousBaseURL"] as? String
            AppLogger.networking.info("Server environment changed → \(NetworkHandler.resolvedEnvironment.rawValue); re-fetching and re-registering (previous: \(previousBaseURL ?? "—"))")
            // Drop WebSocket so it reconnects against the new host.
            self.webSocketTask?.cancel()
            self.webSocketTask = nil
            self.getInfo(backgroundRefresh: false)
            #if canImport(ActivityKit) && os(iOS)
            Task { @MainActor in
                if let previousBaseURL {
                    await self.deregisterTokens(against: previousBaseURL)
                }
                self.sendPushToStartRegistration()
                await self.reRegisterAllLiveActivities()
            }
            #endif
        }
    }

    #if canImport(ActivityKit) && os(iOS)
    /// Best-effort cleanup against the host we just left. Failures are logged
    /// (the previous host may be unreachable — e.g. Mac asleep, Tailscale off)
    /// but never block re-registration on the new host. Server TTLs are the
    /// fallback if the deregister never reaches the previous server.
    @MainActor
    private func deregisterTokens(against previousBaseURL: String) async {
        if let pts = currentPushToStartToken {
            do {
                try await NetworkHandler.deregisterPushToStart(token: pts, previousBaseURL: previousBaseURL)
                AppLogger.liveActivity.info("Deregistered push-to-start token against \(previousBaseURL)")
            } catch {
                AppLogger.liveActivity.notice("Push-to-start deregister failed against \(previousBaseURL): \(error.localizedDescription)")
            }
        }
        for activity in Activity<LiveSportActivityAttributes>.activities {
            guard let tokenData = activity.pushToken else { continue }
            let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
            do {
                try await NetworkHandler.deregisterLiveActivity(token: tokenString, previousBaseURL: previousBaseURL)
                AppLogger.liveActivity.info("Deregistered activity token \(tokenString.prefix(12))... against \(previousBaseURL)")
            } catch {
                AppLogger.liveActivity.notice("Activity deregister failed against \(previousBaseURL): \(error.localizedDescription)")
            }
        }
    }
    #endif

    /// Re-posts each active Live Activity's push token to the newly-resolved server.
    /// Gaps until the next update cycle are acceptable — this is a developer tool.
    @MainActor
    private func reRegisterAllLiveActivities() async {
        #if canImport(ActivityKit) && os(iOS)
        let activities = Activity<LiveSportActivityAttributes>.activities
        var successes = 0
        var lastTokenPrefix: String?
        for activity in activities {
            guard let tokenData = activity.pushToken else { continue }
            let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
            lastTokenPrefix = String(tokenString.prefix(12))
            do {
                try await NetworkHandler.subscribeToLiveActivityUpdate(
                    token: tokenString,
                    eventID: activity.attributes.eventID,
                    homeTeam: activity.attributes.homeTeam,
                    awayTeam: activity.attributes.awayTeam
                )
                successes += 1
            } catch {
                PushRegistrationDiagnostics.shared.recordFailure(
                    env: NetworkHandler.resolvedEnvironment,
                    tokenPrefix: lastTokenPrefix,
                    error: "LA re-register failed: \(error.localizedDescription)"
                )
                AppLogger.liveActivity.error("LA re-register failed for \(activity.attributes.eventID): \(error.localizedDescription)")
            }
        }
        if successes > 0 || !activities.isEmpty {
            PushRegistrationDiagnostics.shared.recordSuccess(
                env: NetworkHandler.resolvedEnvironment,
                tokenPrefix: lastTokenPrefix ?? "—",
                liveActivities: successes
            )
        }
        #endif
    }
    
    private func handleLiveGames() async throws {
        AppLogger.networking.info("Getting live games")
        var liveInfo = try await NetworkHandler.getLiveSnapshot()
        // Merge live scores into schedule before filtering out completed games
        mergeLiveIntoSchedule(liveInfo)
        liveInfo.removeNonStarting()
        liveInfo.removeOtherInfo()
        self.currentLiveInfo = liveInfo
        updateLiveData()
        if let liveInfo = currentLiveInfo {
            liveCache?.insert(liveInfo, for: "live")
        }
        try liveCache?.saveToDisk(with: Self.cacheStem(base: "live"))
    }
    
    private func handleTeams() async throws {
        AppLogger.networking.info("Getting teams")
        async let teams = NetworkHandler.getTeams()
        self.teams = try await teams
        buildTeamLookupCaches()
        teamCache?.insert(self.teams, for: "teams")
        try teamCache?.saveToDisk(with: Self.cacheStem(base: "teams"))
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
        // No session means the VM was built without networking (snapshot/unit
        // tests) — never fall through to URLSession.shared and open a real socket.
        guard let session = webSocketSession else { return }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        wsReconnectAttempts = 0
        webSocketTask = NetworkHandler.connectWebSocketForLive(session: session)
        webSocketTask?.resume()
        Task { @MainActor [weak self] in
            do {
                try await self?.receiveMessages()
            } catch {
                AppLogger.networking.error("WebSocket receive error: \(error.localizedDescription)")
                self?.webSocketTask = nil
                self?.wsFatalFrameError = NetworkHandler.isOversizedFrameError(error)
                self?.reconnectWebSocketOnly()
            }
        }
    }

    // MARK: - Developer replay

    /// Developer-only: replay a completed game as if it were live. Reconnects the live
    /// WebSocket to the server's `/replay/:eventID` endpoint, sends the selected game as
    /// the shell, and lets the normal receive→merge→liveEvents→LiveActivity pipeline drive
    /// the rest. Requires the app to be pointed at a local/dev server (the endpoint is
    /// dev-gated). Team sports only (NBA/NFL/NHL/MLB/soccer).
    /// First WS frame sent to `/replay`: the game shell plus client-fetched plays.
    private struct ReplayHandshakePayload: Encodable {
        let shell: Game
        let plays: [Play]
    }

    /// Result of probing whether a game can be replayed — the play-by-play and where it came from.
    struct ReplayAvailability {
        let plays: [Play]
        let source: ReplaySource
    }

    /// Probes whether a game has play-by-play to replay: current server first, then production.
    /// Pure (no state mutation) so the dev UI can call it per row to gate the Replay button.
    /// Returns `nil` when no play-by-play is available anywhere.
    func checkReplayAvailability(for game: Game) async -> ReplayAvailability? {
        guard let eventID = game.idEvent, !eventID.isEmpty else { return nil }
        let slugs = replayESPNSlugs(for: game)
        if let cached = try? await NetworkHandler.fetchPlayByPlay(
            eventID: eventID, sport: slugs?.sport, league: slugs?.league
        ), !cached.plays.isEmpty {
            return ReplayAvailability(plays: cached.plays, source: .localServer)
        }
        if let cached = try? await NetworkHandler.fetchPlayByPlayFromProduction(
            eventID: eventID, sport: slugs?.sport, league: slugs?.league
        ), !cached.plays.isEmpty {
            return ReplayAvailability(plays: cached.plays, source: .production)
        }
        return nil
    }

    /// Replay a game. `availability` should be supplied by the dev UI (which has already
    /// confirmed play-by-play exists); when nil, this probes for it and fails if none is found.
    func startReplay(game: Game, speed: Double = 8.0, availability: ReplayAvailability? = nil) {
        guard webSocketSession != nil else {
            AutoFollowLogger.shared.log("Replay: no WebSocket session (networking disabled)", level: .error)
            return
        }
        guard let eventID = game.idEvent, !eventID.isEmpty else {
            AutoFollowLogger.shared.log("Replay: game has no event ID", level: .error)
            return
        }

        isReplaying = true
        replayingGame = game
        replayPhase = .fetching
        replaySource = availability?.source
        replayTotalPlays = 0
        replayFramesReceived = 0
        AutoFollowLogger.shared.log("Replay: preparing \(game.strHomeTeam) vs \(game.strAwayTeam)…", level: .info)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let resolved: ReplayAvailability?
            if let availability {
                resolved = availability
            } else {
                resolved = await self.checkReplayAvailability(for: game)
            }
            // Bail if the user already stopped, or nothing came back.
            guard self.isReplaying else { return }
            guard let resolved, !resolved.plays.isEmpty else {
                AutoFollowLogger.shared.log("Replay: no play-by-play available for this game (tried local + production)", level: .error)
                self.replayPhase = .failed
                self.isReplaying = false
                self.replayingGame = nil
                return
            }
            self.replaySource = resolved.source
            self.beginReplayStream(game: game, eventID: eventID, plays: resolved.plays, speed: speed)
        }
    }

    /// ESPN (sport, league) slugs for a team-sport game, used to fetch its play-by-play.
    private func replayESPNSlugs(for game: Game) -> (sport: String, league: String)? {
        guard let idLeague = game.idLeague, let leagueInt = Int(idLeague),
              let league = Leagues(rawValue: leagueInt) else { return nil }
        if league.isBasketball { return ("basketball", league.espnSlug ?? "nba") }
        if league == .nfl { return ("football", "nfl") }
        if league == .nhl { return ("hockey", "nhl") }
        if league == .mlb { return ("baseball", "mlb") }
        if league.isSoccer, let slug = league.espnSlug { return ("soccer", slug) }
        return nil
    }

    private func beginReplayStream(game: Game, eventID: String, plays: [Play], speed: Double) {
        guard let session = webSocketSession else { return }
        replayTotalPlays = plays.count
        replayFramesReceived = 0
        replayPhase = .streaming
        NetworkHandler.replayTarget = (eventID: eventID, speed: speed)

        restartTimer?.invalidate()
        restartTimer = nil
        wsReconnectAttempts = 0
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        let task = NetworkHandler.connectWebSocketForLive(session: session)
        webSocketTask = task
        task.resume()

        // Send the shell + plays as the first frame; the server paces them back as LiveScore.
        let payload = ReplayHandshakePayload(shell: game, plays: plays)
        if let data = try? JSONEncoder().encode(payload),
           let string = String(data: data, encoding: .utf8) {
            task.send(.string(string)) { error in
                if let error {
                    AppLogger.networking.error("Replay handshake send failed: \(error.localizedDescription)")
                }
            }
        }
        AutoFollowLogger.shared.log("Replay started: \(game.strHomeTeam) vs \(game.strAwayTeam) — \(plays.count) plays at \(speed)x", level: .success)

        Task { @MainActor [weak self] in
            do {
                try await self?.receiveMessages()
            } catch {
                // Stream ended or errored. During replay we do NOT auto-reconnect (that
                // would re-dial /replay without a shell and loop); just drop the socket and
                // reset state so the UI doesn't lie about an active replay.
                guard let self, self.isReplaying else { return }
                self.webSocketTask = nil
                self.isReplaying = false
                self.replayingGame = nil
                self.replayPhase = self.replayFramesReceived > 0 ? .ended : .failed
                NetworkHandler.replayTarget = nil
                AutoFollowLogger.shared.log("Replay ended after \(self.replayFramesReceived)/\(self.replayTotalPlays) frames", level: .warning)
                AppLogger.networking.info("Replay stream ended: \(error.localizedDescription)")
            }
        }
    }

    /// Stops an in-progress replay and returns the live socket to normal `/ws` behavior.
    func stopReplay() {
        guard isReplaying else { return }
        isReplaying = false
        replayingGame = nil
        replayPhase = nil
        replaySource = nil
        replayTotalPlays = 0
        replayFramesReceived = 0
        NetworkHandler.replayTarget = nil
        restartTimer?.invalidate()
        restartTimer = nil
        wsReconnectAttempts = 0
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        AutoFollowLogger.shared.log("Replay stopped — resuming live", level: .info)
        handleLiveWebsocket()
    }

    /// Clears a finished replay's status badge (no-op while a replay is active).
    func clearReplayStatus() {
        guard !isReplaying else { return }
        replayPhase = nil
        replaySource = nil
        replayTotalPlays = 0
        replayFramesReceived = 0
    }

    func reconnectWebSocketOnly() {
        // Replay drives its own (non-reconnecting) socket — never auto-reconnect over it.
        guard !isReplaying else { return }
        // While the network path is down, don't burn attempts — the path-monitor
        // callback in `startPathMonitor` will reset attempts and force a reconnect
        // the moment connectivity returns.
        guard hasNetworkPath else {
            if appStorage.debugMode {
                AppLogger.networking.info("WebSocket reconnect deferred — network path unsatisfied")
            }
            return
        }
        wsReconnectAttempts += 1
        // Fatal oversized-frame error: the server is pushing a frame larger than the
        // client cap, so reconnecting just reproduces the same failure on the next
        // frame. Don't hammer the socket — pull live data over REST (HTTP is gzip'd
        // and has no frame cap) and retry the socket on a slow fixed interval until
        // the server-side payload shrinks back under the cap.
        let delay: TimeInterval
        if wsFatalFrameError {
            AppLogger.networking.warning("WebSocket frame exceeds client cap — falling back to REST live refresh; slow socket retry in 300s")
            Task { @MainActor [weak self] in try? await self?.handleLiveGames() }
            delay = 300
        } else {
            // Quadratic backoff capped at 60s: 2, 8, 18, 32, 50, 60, 60... — keep retrying
            // forever so a long outage doesn't permanently silence live updates.
            delay = WebSocketBackoff.delaySeconds(forAttempt: wsReconnectAttempts)
        }
        if appStorage.debugMode {
            AppLogger.networking.info("WebSocket reconnect attempt \(self.wsReconnectAttempts) in \(delay)s")
        }
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.restartTimer = nil
            guard let session = self?.webSocketSession else { return }
            self?.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self?.webSocketTask = nil
            self?.webSocketTask = NetworkHandler.connectWebSocketForLive(session: session)
            self?.webSocketTask?.resume()
            Task { @MainActor [weak self] in
                do {
                    try await self?.receiveMessages()
                } catch {
                    AppLogger.networking.error("WebSocket receive error (reconnect): \(error.localizedDescription)")
                    self?.webSocketTask = nil
                    self?.wsFatalFrameError = NetworkHandler.isOversizedFrameError(error)
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
            return appStorage.shouldShowSoccer || appStorage.shouldShowWorldCup
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
        // Single aggregated fetch — server already returns the full LiveScore from one
        // Redis-cached endpoint, so per-sport fan-out was redundant.
        // NetworkHandler.handleCall is nonisolated, so the network + JSONDecoder run on
        // the cooperative thread pool, not main.
        AppLogger.networking.info("Requesting full schedule snapshot")
        let snapshot = try await NetworkHandler.handleCall()

        await applySnapshotIncrementally(snapshot)

        gameCache?.insert(snapshot, for: "games")
        try gameCache?.saveToDisk(with: Self.cacheStem(base: "games"))
    }

    /// Order sports for incremental reveal: sports the user has favorites in render first,
    /// then user-enabled sports, then disabled sports (still loaded so the calendar has data).
    /// Favorite-sport detection scans the snapshot once — fast because we're walking arrays
    /// we just decoded.
    private func prioritizedSports(in snapshot: LiveScore) -> [SportType] {
        let favoriteNames = favorites.teams
        var favoriteSports: Set<SportType> = []
        if !favoriteNames.isEmpty {
            for sport in SportType.allCases {
                guard let events = snapshot.event(for: sport)?.events else { continue }
                let hasFavorite = events.contains { game in
                    favoriteNames.contains(game.strHomeTeam) || favoriteNames.contains(game.strAwayTeam)
                }
                if hasFavorite { favoriteSports.insert(sport) }
            }
        }
        let allCases = SportType.allCases
        let withFav = allCases.filter { favoriteSports.contains($0) }
        let enabled = allCases.filter { shouldAddTask(sport: $0) && !favoriteSports.contains($0) }
        let disabled = allCases.filter { !shouldAddTask(sport: $0) && !favoriteSports.contains($0) }
        return withFav + enabled + disabled
    }

    /// Reveals the freshly-fetched snapshot one sport at a time so SwiftUI can paint
    /// favorites within the first frame after the response lands. Each iteration runs
    /// a per-sport mutation, then yields so the run-loop commits a frame before the
    /// next slice starts. A final filterSports(force:true) reconcile guarantees
    /// end-state consistency with the legacy single-shot setGames path.
    @MainActor
    private func applySnapshotIncrementally(_ snapshot: LiveScore) async {
        // Reveal-from-empty is only for the FIRST paint, when the Games tab is still
        // blank and favorites should appear ASAP. On a refresh we already have a full
        // list on screen — rebuilding `totalGames` from [] would wipe every section
        // for a frame per sport until its slice lands. The World Cup hero is the most
        // visible casualty: its games ride the soccer slice, so until soccer is
        // reached `worldCupGamesWithTeams` is empty and the hero collapses (or, on a
        // non-today matchday page, unmounts entirely), reading as a flash. When data
        // is already present, swap to the new snapshot in one shot (also cheaper: one
        // filter pass, not N).
        if !(totalGames?.isEmpty ?? true) {
            setGames(result: snapshot)
            return
        }

        let order = prioritizedSports(in: snapshot)

        // Reset team-resolution caches up front so per-slice GameWithTeams lookups
        // pick up the new state immediately.
        gameWithTeamsCache.removeAll()
        gamesWithTeamsDateCache.removeAll()

        var accumulated: [Game] = []
        var firstSliceRendered = false

        for sport in order {
            let sportGames = snapshot.event(for: sport)?.events ?? []
            gamesDict[sport] = sportGames

            // F1 standings ride along with the racing slice
            if sport == .racing, let standings = snapshot.f1Standings {
                f1Standings = standings
            }
            // World Cup enrichment (bracket + Golden Boot) rides along with the soccer slice
            if sport == .soccer, let wc = snapshot.worldCup {
                worldCup = wc
            }

            // An empty sport doesn't change the visible list — appending nothing and
            // re-running the filter would just repaint the identical Games tab and
            // burn a frame. Skip straight to the next slice.
            guard !sportGames.isEmpty else { continue }
            accumulated.append(contentsOf: sportGames)
            totalGames = accumulated

            // Progressive paint of the Games tab only. calendarGames (Calendar tab,
            // not on screen during this load) is intentionally NOT recomputed here:
            // doing it per slice meant 8 filter+sorts over a growing array — the
            // dominant cost in the load-time hang. The single authoritative
            // filterSports(force:) below rebuilds it once at end-state.
            filteredGames = filterAndSortGamesFromUserPreferences(games: getGamesFromUserPreferences())

            if !firstSliceRendered {
                networkState = .loaded
                firstSliceRendered = true
            }

            // Let SwiftUI commit a frame before we move to the next sport.
            await Task.yield()
        }

        // Final reconcile: rebuilds sport-counts cache, runs handleSearch / sortByDate /
        // setFavorites / updateLiveData / widget snapshot / Spotlight indexing / intent
        // donation. skipLiveUpdate=false so live-event-with-teams views see fresh data.
        filterSports(force: true, skipLiveUpdate: false)
    }
    
    @objc
    private func getData() async {
        // Phase 1: Fetch teams + live snapshot first (fast), then connect WebSocket immediately.
        // This ensures live games appear without waiting for full schedule fetch.
        var fetchFailed = await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask {
                do { try await self.handleTeams(); return false }
                catch { AppLogger.networking.error("handleTeams failed: \(error.localizedDescription)"); return true }
            }
            group.addTask {
                do { try await self.handleLiveGames(); return false }
                catch { AppLogger.networking.error("handleLiveGames failed: \(error.localizedDescription)"); return true }
            }
            var failed = false
            for await taskFailed in group { failed = failed || taskFailed }
            return failed
        }
        // Re-run after both teams and live data are available so live events render with team badges
        updateLiveData()
        // Reconcile any running Live Activities against the freshly fetched REST snapshot,
        // so activities catch up after the phone was offline without waiting for the next WS push.
        #if canImport(ActivityKit) && os(iOS)
        try? await updateLiveActivities()
        #endif
        // Connect WebSocket only if there are live/upcoming games
        ensureWebSocketConnected()

        // Phase 2: Fetch full schedules (slower, per-sport)
        do { try await self.handleGames() }
        catch {
            AppLogger.networking.error("handleGames failed: \(error.localizedDescription)")
            fetchFailed = true
        }
        // Re-evaluate WebSocket now that we have schedule data
        ensureWebSocketConnected()
        #if canImport(ActivityKit) && os(iOS)
        registerPushToStartIfNeeded()
        observeLiveActivities()
        preCacheFavoriteTeamBadges()
        #endif
        appStorage.cleanupExpiredAutoFollows(games: totalGames ?? [])
        reconcileWorldCupFollows()
        if fetchFailed {
            networkState = .failed
        } else {
            networkState = .loaded
            lastSuccessfulFetch = Date()
        }
        networkFetchTask = nil
    }

    struct WebSocketReceiveTimeout: Error {}

    /// `URLSessionWebSocketTask.receive()` bounded by a timeout. A bare `receive()`
    /// can hang indefinitely when the server disappears without a close frame
    /// (server restart, NAT/Wi-Fi drop) — no error is thrown, so the reconnect
    /// path never fires and live updates silently freeze at the last value. Racing
    /// it against a sleep turns that stall into a throw the caller reconnects on.
    nonisolated static func receive(
        _ webSocket: URLSessionWebSocketTask,
        timeoutSeconds: TimeInterval
    ) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await webSocket.receive() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw WebSocketReceiveTimeout()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw WebSocketReceiveTimeout() }
            return result
        }
    }

    @objc
    func receiveMessages() async throws {
        while let webSocket = webSocketTask {
            // Tight window when we expect live pushes (server sends ≤5s apart during
            // live games); generous otherwise so the 60s idle heartbeat isn't read as
            // a dead socket. Either way a truly stalled connection reconnects instead
            // of freezing forever.
            let timeout: TimeInterval = liveEvents.isEmpty ? 75 : 20
            let webSocketMessage = try await Self.receive(webSocket, timeoutSeconds: timeout)
            #if canImport(ActivityKit) && os(iOS)
            // A successful receive while reconnect attempts are outstanding means the
            // socket just recovered (e.g. from the silent-death timeout). The server
            // may have lost — or never received — our per-activity update tokens, so
            // re-register them now rather than waiting for the next foreground.
            if wsReconnectAttempts > 0 {
                reRegisterAllActivityTokens()
            }
            #endif
            wsReconnectAttempts = 0 // Reset on successful receive
            wsFatalFrameError = false // A frame came through under the cap — clear the fallback latch
            switch webSocketMessage {
            case .string(let jsonString):
                if let jsonData = jsonString.data(using: .utf8) {
                    // Decode off-main via a child Task (inherits priority + cancellation,
                    // unlike Task.detached). 1-2 MB LiveScore decodes ran on main before;
                    // pushed every 5s during live games it was visibly stuttering scrolls.
                    var newLiveInfo = try await Task(priority: .userInitiated) {
                        try NetworkHandler.sharedDecoder.decode(LiveScore.self, from: jsonData)
                    }.value
                    // Merge live scores (including completed games) into schedule before filtering
                    mergeLiveIntoSchedule(newLiveInfo)
                    newLiveInfo.removeNonStarting()
                    newLiveInfo.removeOtherInfo()
                    // No withAnimation: this fires every ~5s during live games and used to
                    // bundle all 10 batch-assigned @Observable mutations into a single SwiftUI
                    // animation transaction, re-evaluating observer bodies mid-scroll and
                    // visibly stuttering the list. Score-text updates don't visibly animate
                    // inside List rows; @Observable still propagates the changes without it.
                    if let currentLiveInfo = currentLiveInfo, currentLiveInfo != newLiveInfo {
                        self.currentLiveInfo = newLiveInfo
                    } else if currentLiveInfo == nil {
                        self.currentLiveInfo = newLiveInfo
                    }
                    if isReplaying { replayFramesReceived += 1 }
                    scheduleLiveDataUpdate()
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
            // Match by event ID first (reliable for F1/golf/tennis where team names change).
            // If scheduled has an idEvent but no live counterpart matches it, do NOT fall back
            // to team-name matching: two games with the same matchup on different dates (e.g.
            // today's completed Avs/Wild vs. Tuesday's scheduled Avs/Wild) would otherwise
            // collide and overwrite the scheduled row with the wrong day's score.
            let live: Game
            if let eventID = scheduled.idEvent {
                guard let match = liveByEventID[eventID] else { continue }
                live = match
            } else {
                let key = "\(scheduled.strHomeTeam.lowercased())|\(scheduled.strAwayTeam.lowercased())|\(scheduled.idLeague ?? "")"
                guard let match = liveByTeams[key] else { continue }
                // Defense in depth: only merge if both games fall on the same calendar day.
                if let scheduledDate = scheduled.standardDate,
                   let liveDate = match.standardDate,
                   !Calendar.current.isDate(scheduledDate, inSameDayAs: liveDate) {
                    continue
                }
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

    /// Test-only: seed fixture data for snapshot rendering. Bypasses network fetch,
    /// marks state as loaded, and triggers filterSports so derived state (today's
    /// games, sorted sections, etc.) is populated.
    func applySnapshotFixtures(games: [Game], liveEvents: [Game] = [], teams: [Team] = [], f1Standings: F1Standings? = nil, worldCup: WorldCupEnrichment? = nil) {
        networkFetchTask?.cancel()
        networkFetchTask = nil
        self.totalGames = games
        self.liveEvents = liveEvents
        self.teams = teams
        buildTeamLookupCaches()
        if let standings = f1Standings {
            self.f1Standings = standings
        }
        if let worldCup {
            self.worldCup = worldCup
        }
        // Group games by sport so filterSports picks them up
        self.gamesDict = Dictionary(grouping: games, by: { game in
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let league = Leagues(rawValue: intLeague) else { return .basketball }
            return SportType(league: league)
        })
        filterSports(force: true, skipLiveUpdate: true)
        networkState = .loaded
    }

    func setGames(result: LiveScore, skipLiveUpdate: Bool = false, skipSideEffects: Bool = false) {
        // Invalidate caches since games changed
        gameWithTeamsCache.removeAll()
        gamesWithTeamsDateCache.removeAll()

        totalGames = [result.nhl?.events, result.nfl?.events, result.soccer?.events, result.mlb?.events, result.nba?.events, result.golf?.events, result.tennis?.events, result.racing?.events]
            .compactMap({$0})
            .flatMap({$0})
        if let standings = result.f1Standings {
            f1Standings = standings
        }
        if let wc = result.worldCup {
            worldCup = wc
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
        if appStorage.shouldShowSoccer || appStorage.shouldShowWorldCup {
            let soccerGames = (gamesDict[.soccer] ?? []).filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return league.isSoccer && soccerGamePassesEnableGate(league) && !appStorage.hiddenCompetitions.contains(where: {$0 == league.leagueName})
            }
            allGames.append(contentsOf: applyFavoritesFilter(soccerGames, favoritesOnly: appStorage.favoritesOnlySoccer))
        }
        if appStorage.shouldShowMLB {
            let games = gamesDict[.mlb] ?? []
            allGames.append(contentsOf: applyFavoritesFilter(games, favoritesOnly: appStorage.favoritesOnlyMLB))
        }
        if appStorage.shouldShowNBA || appStorage.shouldShowWNBA {
            if let basketballGames = gamesDict[.basketball] {
                let filtered = basketballGames.filter { game in
                    guard let leagueString = game.idLeague,
                          let intLeague = Int(leagueString),
                          let league = Leagues(rawValue: intLeague) else { return false }
                    if !league.isBasketball || appStorage.hiddenCompetitions.contains(league.leagueName) { return false }
                    return league == .wnba ? appStorage.shouldShowWNBA : appStorage.shouldShowNBA
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
        if favoritesOnly {
            return games.filter { favorites.matches($0) }
        }
        let perLeague = appStorage.favoritesOnlyCompetitions
        guard !perLeague.isEmpty else { return games }
        return games.filter { game in
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let league = Leagues(rawValue: intLeague),
                  perLeague.contains(league.leagueName) else { return true }
            return favorites.matches(game)
        }
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
    
    /// Hash of every filter knob that affects which games getGamesFromUserPreferences()
    /// returns. Used to scope `gamesWithTeamsDateCache` so cached `[GameWithTeams]`
    /// entries built under one filter state survive when the user toggles a sport
    /// filter and back.
    private func computeFilterStateHash() -> Int {
        var hasher = Hasher()
        hasher.combine(appStorage.shouldShowSoccer)
        hasher.combine(appStorage.shouldShowWorldCup)
        hasher.combine(appStorage.shouldShowMLB)
        hasher.combine(appStorage.shouldShowNBA)
        hasher.combine(appStorage.shouldShowWNBA)
        hasher.combine(appStorage.shouldShowNFL)
        hasher.combine(appStorage.shouldShowNHL)
        hasher.combine(appStorage.shouldShowGolf)
        hasher.combine(appStorage.shouldShowTennis)
        hasher.combine(appStorage.shouldShowRacing)
        hasher.combine(appStorage.favoritesOnlyNBA)
        hasher.combine(appStorage.favoritesOnlyNFL)
        hasher.combine(appStorage.favoritesOnlyNHL)
        hasher.combine(appStorage.favoritesOnlySoccer)
        hasher.combine(appStorage.favoritesOnlyMLB)
        hasher.combine(appStorage.favoritesOnlyGolf)
        hasher.combine(appStorage.favoritesOnlyTennis)
        hasher.combine(appStorage.favoritesOnlyRacing)
        for comp in appStorage.hiddenCompetitions { hasher.combine(comp) }
        for team in favorites.teams { hasher.combine(team) }
        return hasher.finalize()
    }

    func filterSports(searchString: String? = nil, force: Bool = false, skipLiveUpdate: Bool = false, skipSideEffects: Bool = false) {
        // Refresh filter-state hash so subsequent reads/writes use the right scope.
        currentFilterStateHash = computeFilterStateHash()
        // Only purge the entire date cache when the underlying games actually changed
        // (force == true). Filter-only changes don't need to wipe — entries built under
        // the previous filter hash become unreachable but remain valid if the user toggles back.
        if force {
            gamesWithTeamsDateCache.removeAll()
        }

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
        // Invalidate the memoized calendar set — it's rebuilt lazily on next access
        // (Calendar/Browse tab), not eagerly here. filterSports is the single
        // chokepoint for every change that affects calendar membership (data
        // fetches and filter/competition toggles), so nil-ing here is sufficient.
        _calendarGamesCache = nil

        rebuildSportCountsCache()
        AppLogger.viewModel.info("Total games: \(self.totalGames?.count ?? 0), filtered: \(self.filteredGames?.count ?? 0)")
        handleSearch(searchString: searchString)
        sortByDate()
        setFavorites()
        if !skipLiveUpdate {
            updateLiveData()
        }

        // The widget snapshot, Spotlight reindex, and intent donation are skipped
        // on the throwaway cached launch pass — getInfo()'s fetch reconcile runs
        // moments later and does them once against fresh data, instead of 2-3×.
        guard !skipSideEffects else { return }

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
        let spotlightSuggested = engagementTracker?.suggestedTeamNames(excluding: spotlightFavorites) ?? []
        Task.detached(priority: .utility) {
            SpotlightIndexer.indexGames(spotlightGames, favorites: spotlightFavorites, suggestedTeams: spotlightSuggested)
        }

        // Donate intents for proactive Siri suggestions
        donateIntents(games: snapshotGames, suggestedTeams: spotlightSuggested)
        #endif
    }
    #if !WIDGET_EXTENSION
    private func donateIntents(games: [Game], suggestedTeams: Set<String> = []) {
        let favoriteTeams = favorites.teams
        let enabledSports = appStorage.enabledSports
        Task.detached(priority: .utility) {
            let manager = IntentDonationManager.shared

            // Donate TrackGameIntent for favorite and suggested teams with upcoming games today/tomorrow
            let calendar = Calendar.current
            let now = Date()
            guard let endDate = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) else { return }

            for game in games {
                guard let gameDate = game.standardDate,
                      gameDate >= now && gameDate < endDate else { continue }
                let isHomeFav = favoriteTeams.contains(game.strHomeTeam)
                let isAwayFav = favoriteTeams.contains(game.strAwayTeam)
                let isHomeSuggested = suggestedTeams.contains(game.strHomeTeam)
                let isAwaySuggested = suggestedTeams.contains(game.strAwayTeam)
                guard isHomeFav || isAwayFav || isHomeSuggested || isAwaySuggested else { continue }

                let teamName: String
                if isHomeFav {
                    teamName = game.strHomeTeam
                } else if isAwayFav {
                    teamName = game.strAwayTeam
                } else if isHomeSuggested {
                    teamName = game.strHomeTeam
                } else {
                    teamName = game.strAwayTeam
                }
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
        // This uses ALL user-pref games (not limited), keyed by (start-of-day, filterHash)
        // so toggling sport filters doesn't wipe entries built under other filter states.
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
        // Replace entries for the current filter hash; entries under other hashes survive.
        let hash = currentFilterStateHash
        gamesWithTeamsDateCache = gamesWithTeamsDateCache.filter { $0.key.filterHash != hash }
        for (day, games) in dateCache {
            gamesWithTeamsDateCache[DateCacheKey(date: day, filterHash: hash)] = games
        }

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
        let key = DateCacheKey(date: start, filterHash: currentFilterStateHash)

        // Check date cache first (populated by sortByDate)
        if let cached = gamesWithTeamsDateCache[key] {
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
        gamesWithTeamsDateCache[key] = result
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

    /// Returns the next upcoming game of a specific sport after a given date.
    /// Searches filteredGames so it respects user sport preferences.
    func nextGame(for sport: SportType, after date: Date) -> Game? {
        let calendar = Calendar.current
        let startOfNextDay = calendar.startOfDay(for: date).addingTimeInterval(86400)
        return (filteredGames ?? [])
            .filter { $0.sportType == sport && ($0.standardDate ?? .distantPast) >= startOfNextDay }
            .min(by: { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) })
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

    /// Public wrapper so World Cup hub views can resolve teams for a game.
    func gameWithTeams(for game: Game) -> GameWithTeams? {
        makeGameWithTeams(game)
    }

    @ObservationIgnored private var _wcGamesCache: [GameWithTeams] = []
    @ObservationIgnored private var _wcGamesCacheSignature: Int = .min

    /// All FIFA World Cup games (league 4429) wrapped with resolved teams, sorted by date.
    ///
    /// Memoized: the WC hero reads this on every body render — including every
    /// WebSocket live tick — and the resolve (sort + `makeGameWithTeams` team
    /// lookups across the whole ~104-match tournament) is far too heavy to redo
    /// each frame. We rebuild only when the WC fixtures or their live state
    /// actually change. The filter + cheap signature hash still run each call so
    /// reading `totalGames` keeps SwiftUI observation wired up.
    var worldCupGamesWithTeams: [GameWithTeams] {
        let wcID = String(Leagues.FIFA_World_Cup.rawValue)
        let wcGames = (totalGames ?? []).filter { $0.idLeague == wcID }

        var hasher = Hasher()
        hasher.combine(wcGames.count)
        for game in wcGames {
            hasher.combine(game.idEvent)
            hasher.combine(game.intHomeScore)
            hasher.combine(game.intAwayScore)
            hasher.combine(game.strStatus)
            hasher.combine(game.strProgress)
        }
        let signature = hasher.finalize()
        if signature == _wcGamesCacheSignature { return _wcGamesCache }

        let resolved = wcGames
            .sorted { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
            .compactMap { makeGameWithTeams($0) }
        _wcGamesCache = resolved
        _wcGamesCacheSignature = signature
        return resolved
    }

    /// Resolve a World Cup game (and its teams) by ESPN event ID, for bracket navigation.
    func worldCupGameWithTeams(eventID: String) -> GameWithTeams? {
        guard let game = (totalGames ?? []).first(where: { $0.idEvent == eventID }) else { return nil }
        return makeGameWithTeams(game)
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

        // Final fallback: Create team from game data if not found. Derive a sensible
        // abbreviation so an unmatched team never renders as first-3-chars ("NEW").
        if foundHomeTeam == nil {
            foundHomeTeam = Team(
                idTeam: idHomeTeam,
                strTeam: strHomeTeam,
                strTeamShort: Team.shortCode(strTeamShort: nil, name: strHomeTeam),
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

        // Final fallback: Create team from game data if not found. Derive a sensible
        // abbreviation so an unmatched team never renders as first-3-chars ("NEW").
        if foundAwayTeam == nil {
            foundAwayTeam = Team(
                idTeam: idAwayTeam,
                strTeam: strAwayTeam,
                strTeamShort: Team.shortCode(strTeamShort: nil, name: strAwayTeam),
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
        // A developer replay owns the socket; don't tear it down or reconnect to live.
        guard !isReplaying else { return }
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
        try gameCache?.saveToDisk(with: Self.cacheStem(base: "games"))
        try teamCache?.saveToDisk(with: Self.cacheStem(base: "teams"))
        try liveCache?.saveToDisk(with: Self.cacheStem(base: "live"))
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
        // Prefer the full team name over the short code. Short codes collide across
        // sports (both Philadelphia 76ers and Philadelphia Flyers use "PHI"), and the
        // widget reads the badge file by exact filename — so an activity attributed
        // as "PHI" will pick up whichever Philly team's badge was cached last. Full
        // team names like "Philadelphia Flyers" are unique and disambiguate cleanly.
        guard let homeTeamName = homeTeam.strTeam ?? homeTeam.strTeamShort,
              let awayTeamName = awayTeam.strTeam ?? awayTeam.strTeamShort else { throw ModelErrors.unknownTeam(game) }
        let homeShort = homeTeam.strTeamShort
        let awayShort = awayTeam.strTeamShort

        // Download and cache badge images independently (don't require both to succeed)
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal") {
            await withTaskGroup(of: Void.self) { group in
                for team in [homeTeam, awayTeam] {
                    group.addTask {
                        await Self.downloadAndCacheBadge(team: team, containerURL: containerURL)
                    }
                }
            }
        }

        let initialContentState = LiveSportActivityAttributes.ContentState(homeScore: Int(game.intHomeScore ?? "") ?? 0, awayScore: Int(game.intAwayScore ?? "") ?? 0, status: game.strStatus, progress: game.strProgress, lastPlay: nil)
        let activityAttributes = LiveSportActivityAttributes(
            homeTeam: homeTeamName,
            awayTeam: awayTeamName,
            eventID: game.idEvent ?? "",
            homeTeamShort: homeShort,
            awayTeamShort: awayShort
        )
        return (activityAttributes, initialContentState)
    }
    func requestActivity(game: Game, homeTeam: Team, awayTeam: Team) {
        Task { @MainActor in
            do {
                let (activityAttributes, initialContentState) = try await configureDataForLiveActivity(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                // Use the modern ActivityContent API. relevanceScore matters when multiple
                // activities are alive — iOS picks the highest-scored one for compact and
                // surfaces others as minimal pills. Apple's WWDC samples use small values
                // (e.g. 50, 100); the elapsed-seconds approach I tried earlier was orders
                // of magnitude larger and may have been ignored or clamped.
                //
                // Use the game's start time to differentiate: more recently started ⇒
                // higher relevance ⇒ promoted to compact, with the older one as minimal.
                let staleDate = Date().addingTimeInterval(60 * 60 * 8) // 8h iOS max
                let gameStart = game.standardDate ?? Date()
                let elapsedMinutes = max(0, Date().timeIntervalSince(gameStart) / 60)
                // Score in 0...100, decaying with elapsed minutes. A just-started game
                // scores 100; one that's been live for 100+ minutes scores 0.
                let relevance = max(0, 100 - elapsedMinutes)
                let content = ActivityContent(
                    state: initialContentState,
                    staleDate: staleDate,
                    relevanceScore: relevance
                )

                // Idempotent funnel: iOS ActivityKit does not collapse two requests
                // with identical attributes; calling `request` twice for the same
                // eventID would spawn two activities. Check existing activities
                // first and forward to `update` if one is already alive.
                let existingIDs = Activity<LiveSportActivityAttributes>.activities.map { $0.attributes.eventID }
                switch LiveActivityRequestPlanner.plan(existingEventIDs: existingIDs, for: activityAttributes.eventID) {
                case .updateExisting:
                    guard let existing = Activity<LiveSportActivityAttributes>.activities
                        .first(where: { $0.attributes.eventID == activityAttributes.eventID }) else { return }
                    await existing.update(content)
                    // Re-arm the token listener; the underlying AsyncSequence dedups
                    // re-registrations server-side via the install-ID key.
                    observePushTokenUpdates(for: existing)
                    if appStorage.debugMode {
                        AutoFollowLogger.shared.log("Live activity already present — updated in place for \(activityAttributes.eventID)", level: .info)
                    }
                    AppLogger.liveActivity.info("Idempotent update for existing activity \(activityAttributes.eventID)")
                case .createNew:
                    let activity = try Activity.request(
                        attributes: activityAttributes,
                        content: content,
                        pushType: .token
                    )
                    if appStorage.debugMode {
                        AutoFollowLogger.shared.log("Live activity started, observing push token updates...", level: .success)
                    }
                    observePushTokenUpdates(for: activity)
                }
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
                await Self.registerActivityToken(
                    token: tokenString,
                    eventID: eventID,
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    isDebug: isDebug
                )
            }
        }
    }

    /// POSTs a per-activity update token to the server, retrying with backoff.
    /// The previous fire-once POST only logged on failure — a single transient
    /// network error then left the server without the token, so `APNSJob` had
    /// nothing to push to and the Lock Screen activity froze at its start state
    /// until the next foreground re-registration. Retrying closes that window;
    /// WS-reconnect and foreground re-registration remain the longer-term net.
    nonisolated static func registerActivityToken(
        token: String,
        eventID: String,
        homeTeam: String,
        awayTeam: String,
        isDebug: Bool
    ) async {
        let backoffSeconds: [UInt64] = [0, 2, 5, 15, 30]
        for (attempt, delay) in backoffSeconds.enumerated() {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay * 1_000_000_000) }
            do {
                try await NetworkHandler.subscribeToLiveActivityUpdate(token: token, eventID: eventID, homeTeam: homeTeam, awayTeam: awayTeam)
                AppLogger.liveActivity.info("Registered activity update token for \(eventID) (attempt \(attempt + 1))")
                if isDebug {
                    await MainActor.run {
                        AutoFollowLogger.shared.log("Server registered activity token OK (\(homeTeam) vs \(awayTeam))", level: .success)
                    }
                }
                return
            } catch {
                AppLogger.liveActivity.error("Activity token registration attempt \(attempt + 1) failed for \(eventID): \(error.localizedDescription)")
                if isDebug {
                    await MainActor.run {
                        AutoFollowLogger.shared.log("Activity token registration attempt \(attempt + 1) failed: \(error.localizedDescription)", level: .error)
                    }
                }
            }
        }
        AppLogger.liveActivity.error("Gave up registering activity token for \(eventID) after \(backoffSeconds.count) attempts — will retry on WS reconnect / foreground")
    }

    /// Re-registers push tokens for any already-running Live Activities (e.g. after app relaunch).
    func observeLiveActivities() {
        for activity in Activity<LiveSportActivityAttributes>.activities {
            AppLogger.liveActivity.info("Re-observing existing activity for event \(activity.attributes.eventID)")
            observePushTokenUpdates(for: activity)
            // Backfill badges for activities started via push-to-start, where the opponent
            // may not have been a favorite and thus never cached.
            cacheBadgesForActivity(
                eventID: activity.attributes.eventID,
                homeTeam: activity.attributes.homeTeam,
                awayTeam: activity.attributes.awayTeam
            )
        }
    }

    /// Long-running observer that hands every newly-spawned Live Activity off to
    /// `observePushTokenUpdates` for token registration. Critical for the
    /// background-launch case: when a push-to-start arrives, iOS wakes the app
    /// process and creates the Activity, but the user never foregrounds. Without
    /// this listener, the per-activity push token would only be POSTed to the
    /// server once the user opened the app, and the activity would sit at its
    /// initial state with no updates until then.
    ///
    /// Called once from `SportsCalApp.init()` so the subscription is alive
    /// before iOS creates the push-to-start activity. The Task lives for the
    /// whole process lifetime; iOS will stop scheduling us once the activity
    /// stream is idle and the background-launch budget runs out.
    func startActivityUpdatesListener() {
        AppLogger.liveActivity.info("Starting Activity<>.activityUpdates listener for background push-to-start handling")
        Task.detached(priority: .userInitiated) { [weak self] in
            for await activity in Activity<LiveSportActivityAttributes>.activityUpdates {
                AppLogger.liveActivity.info("[activityUpdates] new activity for event \(activity.attributes.eventID) — observing push token")
                await self?.reconcileDuplicateActivities(for: activity)
                await MainActor.run {
                    self?.observePushTokenUpdates(for: activity)
                    self?.cacheBadgesForActivity(
                        eventID: activity.attributes.eventID,
                        homeTeam: activity.attributes.homeTeam,
                        awayTeam: activity.attributes.awayTeam
                    )
                }
            }
        }
    }

    /// Race-resolution for the case where a user-initiated `Activity.request`
    /// and a server-initiated push-to-start both land for the same eventID.
    /// ActivityKit will surface both; we keep one and end the rest.
    ///
    /// Tiebreaker: prefer the activity that already has a push token (the
    /// server can only drive updates on that one). If multiple or none have
    /// tokens, keep the oldest by `activity.id` (stable, no clock skew).
    @MainActor
    private func reconcileDuplicateActivities(for newlySpawned: Activity<LiveSportActivityAttributes>) async {
        let eventID = newlySpawned.attributes.eventID
        let group = Activity<LiveSportActivityAttributes>.activities
            .filter { $0.attributes.eventID == eventID }
        guard group.count > 1 else { return }

        let keeper = group.first(where: { $0.pushToken != nil })
            ?? group.min(by: { $0.id < $1.id })!
        for activity in group where activity.id != keeper.id {
            AppLogger.liveActivity.info("[reconcile] ending duplicate activity \(activity.id) for event \(eventID), keeping \(keeper.id)")
            if appStorage.debugMode {
                AutoFollowLogger.shared.log("Ended duplicate live activity for \(eventID)", level: .info)
            }
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
    }

    /// Re-POSTs the current pushToken for every active Live Activity to the server,
    /// refreshing the Redis registration TTL. Call from foreground transitions and the
    /// BGAppRefresh handler — without this, a quiet stretch (or a denied background grant)
    /// can let the server-side registration expire and silence the activity.
    func reRegisterAllActivityTokens() {
        let isDebug = appStorage.debugMode
        for activity in Activity<LiveSportActivityAttributes>.activities {
            guard let tokenData = activity.pushToken else { continue }
            let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
            let eventID = activity.attributes.eventID
            let homeTeam = activity.attributes.homeTeam
            let awayTeam = activity.attributes.awayTeam
            AppLogger.liveActivity.info("Re-registering activity token for \(eventID): \(tokenString.prefix(12))...")
            Task.detached {
                await Self.registerActivityToken(
                    token: tokenString,
                    eventID: eventID,
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    isDebug: isDebug
                )
            }
        }
    }

    /// Resolves `homeTeam`/`awayTeam` attribute strings back to `Team` objects so their
    /// badges can be cached.
    ///
    /// Prefers eventID-based resolution: looking the game up by `eventID` and using its
    /// `getTeams(for:)` result eliminates the "Philly" ambiguity — a name lookup of "Philly"
    /// could resolve to either the 76ers or the Flyers (whichever was indexed last), but the
    /// game's own team IDs are unambiguous. Falls back to name lookup only when the activity's
    /// eventID isn't in our current data set (e.g., a stale activity from a previous app run).
    ///
    /// Also writes a copy of the badge under the literal attribute string. The widget reads
    /// the badge file by exact filename (`attributes.awayTeam`), so if the activity was
    /// started with a name that isn't `strTeam`/`strTeamShort`, the literal-name copy
    /// ensures the widget still finds an image instead of falling back to initials.
    private func cacheBadgesForActivity(eventID: String, homeTeam: String, awayTeam: String) {
        Task {
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal") else { return }

            // Prefer eventID-based resolution — sport context disambiguates short names.
            let allGames = (totalGames ?? []) + allLiveEvents
            if !eventID.isEmpty,
               let game = allGames.first(where: { $0.idEvent == eventID }),
               let (resolvedHome, resolvedAway) = getTeams(for: game) {
                await Self.writeBadge(name: homeTeam, team: resolvedHome, containerURL: containerURL)
                await Self.writeBadge(name: awayTeam, team: resolvedAway, containerURL: containerURL)
                return
            }

            // Fallback: name lookup. Ambiguous for shared shorthand like "Philly", but
            // better than no badge at all.
            for name in [homeTeam, awayTeam] {
                guard let team = teamByName[name] ?? teamsDictName[name]?.first else { continue }
                await Self.writeBadge(name: name, team: team, containerURL: containerURL)
            }
        }
    }

    /// Writes the team's badge under its canonical names AND a literal copy at `name`,
    /// covering the case where the activity attribute string isn't a canonical name.
    private static func writeBadge(name: String, team: Team, containerURL: URL) async {
        await downloadAndCacheBadge(team: team, containerURL: containerURL)
        let literalURL = containerURL.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: literalURL.path),
           let canonicalName = team.strTeam ?? team.strTeamShort {
            let canonicalURL = containerURL.appendingPathComponent(canonicalName)
            if let data = try? Data(contentsOf: canonicalURL) {
                try? data.write(to: literalURL)
            }
        }
    }
    
    /// Registers for push-to-start Live Activity tokens and sends them to the server
    /// along with the user's favorite teams and auto-followed event IDs.
    func registerPushToStartIfNeeded() {
        guard currentPushToStartPayload() != nil else { return }

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
                let payload = self.currentPushToStartPayload()
                let favoritesList = payload?.favorites ?? []
                let eventIDs = payload?.eventIDs ?? []
                do {
                    try await NetworkHandler.registerPushToStart(token: tokenString, favorites: favoritesList, eventIDs: eventIDs)
                    if appStorage.debugMode {
                        AutoFollowLogger.shared.log("Server registered push-to-start OK", level: .success)
                    }
                    AppLogger.liveActivity.info("Registered push-to-start token with \(favoritesList.count) favorites, \(eventIDs.count) auto-follow events")
                    PushRegistrationDiagnostics.shared.recordSuccess(
                        env: NetworkHandler.resolvedEnvironment,
                        tokenPrefix: String(tokenString.prefix(12)),
                        liveActivities: Activity<LiveSportActivityAttributes>.activities.count
                    )
                } catch {
                    if appStorage.debugMode {
                        AutoFollowLogger.shared.log("Server registration failed: \(error.localizedDescription)", level: .error)
                    }
                    AppLogger.liveActivity.error("Failed to register push-to-start: \(error.localizedDescription)")
                    PushRegistrationDiagnostics.shared.recordFailure(
                        env: NetworkHandler.resolvedEnvironment,
                        tokenPrefix: String(tokenString.prefix(12)),
                        error: error.localizedDescription
                    )
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

    /// Pure registration decision for the current app state — see
    /// `PushToStartRegistrationPlanner` for the rules.
    func currentPushToStartPayload() -> PushToStartPayload? {
        PushToStartRegistrationPlanner.payload(
            autoFollowFavorites: appStorage.autoFollowFavorites,
            favoriteTeams: favorites.teams,
            autoFollowEventIDs: appStorage.autoFollowEventIDs
        )
    }

    /// Sends the current push-to-start token, favorites, and auto-follow event IDs to the server.
    private func sendPushToStartRegistration() {
        guard currentPushToStartPayload() != nil else { return }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Use cached token for immediate re-registration (don't wait for token update)
        if let cachedToken = currentPushToStartToken {
            Task { @MainActor in
                let payload = self.currentPushToStartPayload()
                let favoritesList = payload?.favorites ?? []
                let eventIDs = payload?.eventIDs ?? []
                try? await NetworkHandler.registerPushToStart(token: cachedToken, favorites: favoritesList, eventIDs: eventIDs)
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
                    let payload = self.currentPushToStartPayload()
                    let favoritesList = payload?.favorites ?? []
                    let eventIDs = payload?.eventIDs ?? []
                    try? await NetworkHandler.registerPushToStart(token: tokenString, favorites: favoritesList, eventIDs: eventIDs)
                    AppLogger.liveActivity.info("Re-registered push-to-start with \(favoritesList.count) favorites, \(eventIDs.count) auto-follow events")
                    break
                }
            }
        }
    }

    /// Keeps `autoFollowEventIDs` in sync with the one-tap "Follow World Cup" toggle.
    /// `followWorldCup` is the source of truth; the concrete WC event IDs are recomputed
    /// from the current game list each fetch so new knockout fixtures get followed as the
    /// bracket fills in (and so date-based cleanup doesn't permanently drop them).
    /// Re-registers push-to-start only when the followed set actually changes.
    func reconcileWorldCupFollows() {
        guard appStorage.followWorldCup else { return }
        let wcIDs = appStorage.worldCupEventIDsToFollow(from: totalGames ?? [])
        guard !wcIDs.isEmpty else { return }
        let existing = appStorage.autoFollowEventIDs
        let missing = wcIDs.subtracting(existing)
        guard !missing.isEmpty else { return }
        appStorage.autoFollowEventIDs = existing.union(missing)
        if appStorage.debugMode {
            AutoFollowLogger.shared.log("Follow World Cup: added \(missing.count) matches to auto-follow", level: .success)
        }
        sendAutoFollowRegistration()
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
                await Self.downloadAndCacheBadge(team: team, containerURL: containerURL)
            }
        }
    }

    /// One-shot purge of every top-level file in the App Group container. Earlier
    /// versions of `downloadAndCacheBadge` wrote each team's badge under every
    /// alternate name, which caused cross-team file collisions on shared shorthand
    /// like "Philly", "PHI", or "NY" — whichever team was cached last won. Existing
    /// installs still have those polluted files on disk; this purges them once so
    /// the new canonical-name-only caching can rewrite cleanly. Self-disables via
    /// the `badgePurgeV3` UserDefaults flag.
    static func purgeStaleAppGroupBadgesIfNeeded() {
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        guard defaults?.bool(forKey: "badgePurgeV3") != true else { return }
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal") {
            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(
                at: containerURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for url in contents {
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if !isDirectory {
                        try? fm.removeItem(at: url)
                    }
                }
            }
        }
        defaults?.set(true, forKey: "badgePurgeV3")
        AppLogger.liveActivity.info("Purged stale App Group badge files (one-shot v3)")
    }

    /// Pre-caches badge images for all favorite teams to the app group container.
    func preCacheFavoriteTeamBadges() {
        guard !favorites.teams.isEmpty else { return }

        Task {
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal") else { return }

            // Resolve teams on the main actor before fanning out — teamByName is main-isolated.
            let teams = favorites.teams.compactMap { teamByName[$0] }
            await withTaskGroup(of: Void.self) { group in
                for team in teams {
                    group.addTask {
                        await Self.downloadAndCacheBadge(team: team, containerURL: containerURL)
                    }
                }
            }
        }
    }

    /// Downloads a team's badge and writes it to the app group container under every name
    /// the widget might look up by (short name AND full name). Server push-to-start attributes
    /// use full team names while locally-started activities use short names — caching under both
    /// ensures the widget finds the badge regardless of which path started the activity.
    static func downloadAndCacheBadge(team: Team, containerURL: URL) async {
        // Only cache under canonical names (`strTeamShort`, `strTeam`). Alternates
        // get shared between teams — e.g., both "Philadelphia 76ers" and
        // "Philadelphia Flyers" list "Philly" as an alternate, so writing under
        // alternates causes the second-cached team to overwrite the first and the
        // wrong logo shows up in the widget. The activity-side path
        // (`cacheBadgesForActivity`) writes a per-activity literal-name copy when
        // the attribute string isn't canonical, which preserves Brighton-style
        // recovery without the cross-sport collision.
        let fileNames = Set([team.strTeamShort, team.strTeam].compactMap { $0 }.filter { !$0.isEmpty })
        guard !fileNames.isEmpty else { return }

        // Skip if already cached under all names
        if fileNames.allSatisfy({ FileManager.default.fileExists(atPath: containerURL.appendingPathComponent($0).path) }) {
            return
        }

        guard let badgeString = team.strTeamBadge,
              let badgeURL = URL(string: badgeString.contains("thesportsdb.com") ? badgeString + "/tiny" : badgeString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(for: URLRequest(url: badgeURL, cachePolicy: .returnCacheDataElseLoad))
            guard UIImage(data: data) != nil else {
                AppLogger.liveActivity.notice("Badge data is not a valid image for \(fileNames.joined(separator: ","))")
                return
            }
            for name in fileNames {
                let fileURL = containerURL.appendingPathComponent(name)
                try? data.write(to: fileURL)
            }
        } catch {
            AppLogger.liveActivity.notice("Badge download failed for \(fileNames.joined(separator: ",")): \(error.localizedDescription)")
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
        let lookup = LiveActivityMatcher.buildLookup(from: allLiveEvents)
        for activity in Activity<LiveSportActivityAttributes>.activities {
            if let newState = LiveActivityMatcher.resolveUpdate(
                eventID: activity.attributes.eventID,
                homeTeam: activity.attributes.homeTeam,
                awayTeam: activity.attributes.awayTeam,
                currentState: activity.contentState,
                in: lookup
            ) {
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
