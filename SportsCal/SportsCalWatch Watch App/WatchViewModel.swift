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
    var lastUpdated: Date?

    // Preferences synced from iPhone via WatchConnectivity
    var enabledSports: Set<SportType> = Set(SportType.allCases)
    var favoriteTeams: Set<String> = []
    var hiddenCompetitions: Set<String> = []

    // Polling
    let pollTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private var previousScores: [String: (home: String, away: String)] = [:]

    var hasLiveGames: Bool { !liveGames.isEmpty }

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

    func isLiveGame(_ game: Game) -> Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty &&
               status != "ft" &&
               status != "aet" &&
               status != "not started" &&
               status != "ns" &&
               game.intHomeScore != nil &&
               game.intAwayScore != nil
    }

    // MARK: - Data Loading

    func initialLoad() async {
        loadPreferencesFromLocal()
        loadCachedData()
        await fetchSchedule()
    }

    func refreshOnWake() async {
        if hasLiveGames {
            await fetchLiveScores()
        } else {
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
        return Date().timeIntervalSince(last) > 300 // 5 minutes
    }

    func fetchSchedule() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let sportTypes = Array(enabledSports)
            guard !sportTypes.isEmpty else { return }

            let (fetchedGames, fetchedTeams) = try await NetworkHandler.getWidgetScheduleFor(
                sports: sportTypes,
                limit: 30,
                favorites: Array(favoriteTeams)
            )

            await MainActor.run {
                self.games = fetchedGames
                self.teams = fetchedTeams
                self.liveGames = fetchedGames.filter { self.isLiveGame($0) }
                self.lastUpdated = Date()
            }
            cacheData(games: fetchedGames, teams: fetchedTeams)
        } catch {
            // Silently fail — cached data remains visible
        }
    }

    func fetchLiveScores() async {
        do {
            let liveScore = try await NetworkHandler.getLiveSnapshot()
            let allLive = collectAllGames(from: liveScore)

            await MainActor.run {
                // Detect score changes for haptics
                for game in allLive {
                    checkForScoreChange(game)
                }

                // Merge live data into existing games
                self.liveGames = allLive.filter { self.isLiveGame($0) }
                mergeLiveIntoSchedule(allLive)
            }
        } catch {
            // Silently fail — keep existing data
        }
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

    private func mergeLiveIntoSchedule(_ liveGames: [Game]) {
        var updated = games
        for live in liveGames {
            if let idx = updated.firstIndex(where: { $0.idEvent == live.idEvent }) {
                updated[idx] = live
            }
        }
        games = updated
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

        // Use cache if less than 2 hours old
        let age = Date().timeIntervalSince(snapshot.updatedAt)
        guard age < 7200 else { return }

        games = snapshot.games
        teams = snapshot.teams
        liveGames = snapshot.games.filter { isLiveGame($0) }
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
        if defaults.bool(forKey: "shouldShowNFL") { sports.insert(.nfl) }
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
        Task { await fetchSchedule() }
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
        defaults.set(enabledSports.contains(.nfl), forKey: "shouldShowNFL")
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
