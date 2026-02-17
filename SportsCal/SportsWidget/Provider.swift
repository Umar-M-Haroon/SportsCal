//
//  Provider.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/30/22.
//

import Foundation
import WidgetKit
import SwiftUI
import Combine
import SportsCalModel
#if !os(watchOS)
import Sentry
#endif
import os

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: SportsWidgetIntent
    let game: [Game]?
    var images: [String: Data]?
    let teams: [Team]
    var relevance: TimelineEntryRelevance?
}

// MARK: - Widget Image Cache
/// Caches team badge images in the app group container to avoid fetching every timeline refresh
class WidgetImageCache {
    static let shared = WidgetImageCache()

    private let cacheDirectory: URL?
    private let cacheExpirationInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    private init() {
        #if os(watchOS)
        cacheDirectory = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("ImageCache", isDirectory: true)
        #else
        cacheDirectory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent("ImageCache", isDirectory: true)
        #endif

        // Create cache directory if needed
        if let cacheDir = cacheDirectory {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }

    /// Get cached image data or nil if not cached/expired
    func getCachedImage(for teamID: String) -> Data? {
        guard let cacheDir = cacheDirectory else { return nil }

        let fileURL = cacheDir.appendingPathComponent("\(teamID).png")
        let metadataURL = cacheDir.appendingPathComponent("\(teamID).meta")

        // Check if cache exists and is not expired
        guard FileManager.default.fileExists(atPath: fileURL.path),
              FileManager.default.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        // Check expiration
        if let metadataData = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(ImageCacheMetadata.self, from: metadataData) {
            if Date().timeIntervalSince(metadata.cachedAt) > cacheExpirationInterval {
                // Cache expired, remove files
                try? FileManager.default.removeItem(at: fileURL)
                try? FileManager.default.removeItem(at: metadataURL)
                return nil
            }
        }

        return try? Data(contentsOf: fileURL)
    }

    /// Cache image data for a team
    func cacheImage(_ data: Data, for teamID: String) {
        guard let cacheDir = cacheDirectory else { return }

        let fileURL = cacheDir.appendingPathComponent("\(teamID).png")
        let metadataURL = cacheDir.appendingPathComponent("\(teamID).meta")

        do {
            try data.write(to: fileURL)

            let metadata = ImageCacheMetadata(teamID: teamID, cachedAt: Date())
            let metadataData = try JSONEncoder().encode(metadata)
            try metadataData.write(to: metadataURL)
        } catch {
            AppLogger.widget.error("Failed to cache image for team \(teamID): \(error.localizedDescription)")
        }
    }

    /// Get image from cache or fetch from network
    func getImage(for teamID: String, imageURL: String) async throws -> Data {
        // Check cache first
        if let cachedData = getCachedImage(for: teamID) {
            AppLogger.widget.info("[imageCache] hit for team \(teamID): \(cachedData.count) bytes")
            return cachedData
        }

        // Fetch from network
        AppLogger.widget.info("[imageCache] miss for team \(teamID), fetching from network")
        let data = try await NetworkHandler.getImageFor(url: imageURL, size: .tiny)
        AppLogger.widget.info("[imageCache] fetched team \(teamID): \(data.count) bytes")

        // Cache the result
        cacheImage(data, for: teamID)

        return data
    }
}

struct ImageCacheMetadata: Codable {
    let teamID: String
    let cachedAt: Date
}

/// Returns the current resident memory in MB (approximate, for debugging widget OOM)
private func widgetMemoryMB() -> String {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    if result == KERN_SUCCESS {
        let mb = Double(info.resident_size) / (1024 * 1024)
        return String(format: "%.1fMB", mb)
    }
    return "??MB"
}

class Provider: AppIntentTimelineProvider {
    let sampleGames: [Game] = [
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00", isoDate: nil),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134876", idAwayTeam: "134881", strHomeTeam: "Milwaukee Bucks", strAwayTeam: "Denver Nuggets", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00", isoDate: nil),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134877", idAwayTeam: "134882", strHomeTeam: "Golden State Warriors", strAwayTeam: "Boston Celtics", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00", isoDate: nil),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134878", idAwayTeam: "134883", strHomeTeam: "Los Angeles Lakers", strAwayTeam: "Houston Rockets", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00", isoDate: nil),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134879", idAwayTeam: "134884", strHomeTeam: "Seattle Supersonics", strAwayTeam: "Washington Wizards", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00", isoDate: nil),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134874", idAwayTeam: "134885", strHomeTeam: "Detroit Pistons", strAwayTeam: "Portland Trailblazers", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00", isoDate: nil)
    ]

    var sampleImages: [String: Data] {
        #if canImport(UIKit)
        return ["134875": UIImage(systemName: "basketball.circle.fill")!.pngData()!, "134880": UIImage(systemName: "basketball.circle")!.pngData()!,
                "134876": UIImage(systemName: "basketball.circle")!.pngData()!, "134881": UIImage(systemName: "basketball.circle.fill")!.pngData()!,
                "134877": UIImage(systemName: "basketball")!.pngData()!, "134882": UIImage(systemName: "basketball.fill")!.pngData()!,
                "134878": UIImage(systemName: "basketball.circle.fill")!.pngData()!, "134883": UIImage(systemName: "basketball")!.pngData()!,
                "134879": UIImage(systemName: "basketball.fill")!.pngData()!, "134884": UIImage(systemName: "basketball.circle")!.pngData()!,
                "134874": UIImage(systemName: "basketball.circle.fill")!.pngData()!, "134885": UIImage(systemName: "basketball.fill")!.pngData()!]
        #else
        return [:]
        #endif
    }

    let teams: [Team] = [
        Team.init(idTeam: "134875", strTeam: "Dallas Mavericks", strTeamShort: "DAL", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134876", strTeam: "Milwaukee Bucks", strTeamShort: "MIL", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134877", strTeam: "Golden State Warriors", strTeamShort: "GSW", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134878", strTeam: "Los Angeles Lakers", strTeamShort: "LAL", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134879", strTeam: "Seattle Supersonics", strTeamShort: "SEA", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134874", strTeam: "Detroit Pistons", strTeamShort: "DET", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134880", strTeam: "Utah Jazz", strTeamShort: "UTA", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134881", strTeam: "Denver Nuggets", strTeamShort: "DEN", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134882", strTeam: "Boston Celtics", strTeamShort: "BOS", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134883", strTeam: "Houston Rockets", strTeamShort: "HOU", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134884", strTeam: "Washington Wizards", strTeamShort: "WAS", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134875", strTeam: "Portland Trailblazers", strTeamShort: "POR", strAlternate: nil, strTeamBadge: nil),
    ]

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: SportsWidgetIntent(), game: sampleGames, images: sampleImages, teams: teams)
    }

    func snapshot(for configuration: SportsWidgetIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: configuration, game: sampleGames, images: sampleImages, teams: teams)
    }

    func getImagesFor(homeTeam: Team, awayTeam: Team) async throws -> [String: Data] {
        guard let homeImageURL = homeTeam.strTeamBadge,
              let homeID = homeTeam.idTeam,
              let awayImageURL = awayTeam.strTeamBadge,
              let awayID = awayTeam.idTeam else {
            return [:]
        }

        // Use cached images when available
        let cache = WidgetImageCache.shared
        async let homeImage = cache.getImage(for: homeID, imageURL: homeImageURL)
        async let awayImage = cache.getImage(for: awayID, imageURL: awayImageURL)

        return [homeID: try await homeImage, awayID: try await awayImage]
    }

    func timeline(for configuration: SportsWidgetIntent, in context: Context) async -> Timeline<SimpleEntry> {
        await timelineHandler(configuration: configuration)
    }

    /// Max games to keep in a timeline entry (large widget shows 6)
    private static let maxDisplayGames = 6
    /// Max games to fetch images for (keep memory under widget 30MB limit)
    private static let maxImageGames = 3

    func timelineHandler(configuration: SportsWidgetIntent) async -> Timeline<SimpleEntry> {
        let currentDate = Date()
        AppLogger.widget.info("[timeline] START mem=\(widgetMemoryMB())")

        // Read day offset for interactive navigation
        #if os(watchOS)
        // Watch complications always show today
        let dayOffset = 0
        #else
        let dayOffset = UserDefaults(suiteName: "group.Komodo.SportsCal")?.integer(forKey: "widgetDayOffset") ?? 0
        #endif
        let targetDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: currentDate) ?? currentDate

        // Auto-reset offset at midnight
        #if !os(watchOS)
        if dayOffset != 0 {
            let startOfToday = Calendar.current.startOfDay(for: currentDate)
            let offsetSetDate = UserDefaults(suiteName: "group.Komodo.SportsCal")?.object(forKey: "widgetDayOffsetDate") as? Date
            if let setDate = offsetSetDate, setDate < startOfToday {
                UserDefaults(suiteName: "group.Komodo.SportsCal")?.set(0, forKey: "widgetDayOffset")
            }
        }
        #endif

        let hiddenLeagues = hiddenLeagueNames(for: configuration)

        var (games, teams) = await handleNetworking(
            favoriteOnly: configuration.favoritesOnly,
            sport: configuration.sport,
            targetDate: targetDate,
            hiddenLeagues: hiddenLeagues
        )
        AppLogger.widget.info("[timeline] after networking: \(games.count) games, \(teams.count) teams, mem=\(widgetMemoryMB())")

        // Trim to only what the widget can display — frees memory from large schedules
        games = Array(games.prefix(Self.maxDisplayGames))

        let hasLiveGames = games.contains { isLiveGame($0) }
        let hasUpcomingSoon = games.contains { game in
            guard let date = game.standardDate else { return false }
            return date.timeIntervalSinceNow > 0 && date.timeIntervalSinceNow < 3600
        }

        // Calculate relevance
        let relevance: TimelineEntryRelevance?
        if hasLiveGames {
            relevance = TimelineEntryRelevance(score: 100, duration: 300)
        } else if hasUpcomingSoon {
            relevance = TimelineEntryRelevance(score: 50)
        } else {
            relevance = TimelineEntryRelevance(score: 10)
        }

        #if os(watchOS)
        // Watch: tighter refresh for favorite live games, skip images entirely
        let hasFavoriteLive = games.contains { game in
            isLiveGame(game) && Favorites().contains(game)
        }
        let refreshInterval: TimeInterval = hasFavoriteLive ? 300 : (hasLiveGames ? 600 : 1800)
        #else
        let refreshInterval: TimeInterval = hasLiveGames ? 600 : 1800
        #endif
        let entryDate = currentDate.addingTimeInterval(refreshInterval)

        // Fetch images only for team sports (individual sports don't have team badges),
        // and only for the first few games to stay under the memory limit.
        // watchOS complications use text abbreviations only — skip image fetching entirely.
        var allImages: [String: Data] = [:]
        #if !os(watchOS)
        let teamGames = games.filter { !$0.isIndividualSport }.prefix(Self.maxImageGames)
        AppLogger.widget.info("[timeline] fetching images for \(teamGames.count) team games, mem=\(widgetMemoryMB())")
        for game in teamGames {
            if let homeTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idHomeTeam),
               let awayTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idAwayTeam),
               let images = try? await getImagesFor(homeTeam: homeTeam, awayTeam: awayTeam) {
                let totalBytes = images.values.reduce(0) { $0 + $1.count }
                AppLogger.widget.info("[timeline] fetched image pair: \(totalBytes) bytes, mem=\(widgetMemoryMB())")
                allImages.merge(images, uniquingKeysWith: { $1 })
            }
        }
        #endif

        let totalImageBytes = allImages.values.reduce(0) { $0 + $1.count }
        AppLogger.widget.info("[timeline] DONE \(games.count) games, \(allImages.count) images (\(totalImageBytes) bytes), mem=\(widgetMemoryMB())")

        let entry = SimpleEntry(
            date: entryDate,
            configuration: configuration,
            game: games,
            images: allImages.isEmpty ? nil : allImages,
            teams: teams,
            relevance: relevance
        )

        return Timeline(entries: [entry], policy: .after(entryDate))
    }

    /// Returns the set of league names that should be hidden based on widget config or app defaults
    private func hiddenLeagueNames(for configuration: SportsWidgetIntent) -> Set<String> {
        let selected = configuration.selectedLeagues
        if !selected.isEmpty {
            // Explicit widget override — hide everything NOT selected
            let selectedNames = Set(selected.map(\.leagueName))
            let allMultiLeagueNames = Set(
                Leagues.allCases
                    .filter { $0.isSoccer || $0.isTennis }
                    .map(\.leagueName)
            )
            return allMultiLeagueNames.subtracting(selectedNames)
        }
        // Fallback: app's hiddenCompetitions
        #if os(watchOS)
        let hidden = UserDefaults.standard
            .stringArray(forKey: "hiddenCompetitions") ?? []
        #else
        let hidden = UserDefaults(suiteName: "group.Komodo.SportsCal")?
            .stringArray(forKey: "hiddenCompetitions") ?? []
        #endif
        return Set(hidden)
    }

    /// Filters out games belonging to hidden leagues
    private func applyLeagueFilter(_ games: [Game], hiddenLeagues: Set<String>) -> [Game] {
        guard !hiddenLeagues.isEmpty else { return games }
        return games.filter { game in
            guard let name = game.strLeague else { return true }
            return !hiddenLeagues.contains(name)
        }
    }

    /// Returns the list of enabled sport types based on the intent configuration
    private func enabledSportTypes(for sport: SportSelection) -> [SportType] {
        if let single = sport.sportType {
            return [single]
        }

        // All Sports mode: read user preferences
        // watchOS: read from standard UserDefaults (synced via WatchConnectivity)
        // iOS/macOS: read from shared app group
        #if os(watchOS)
        let defaults = UserDefaults.standard
        #else
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        #endif
        var sports: [SportType] = []
        if defaults?.bool(forKey: "shouldShowNBA") ?? false { sports.append(.basketball) }
        if defaults?.bool(forKey: "shouldShowSoccer") ?? false { sports.append(.soccer) }
        if defaults?.bool(forKey: "shouldShowNHL") ?? false { sports.append(.hockey) }
        if defaults?.bool(forKey: "shouldShowMLB") ?? false { sports.append(.mlb) }
        if defaults?.bool(forKey: "shouldShowNFL") ?? false { sports.append(.nfl) }
        if defaults?.bool(forKey: "shouldShowGolf") ?? false { sports.append(.golf) }
        if defaults?.bool(forKey: "shouldShowTennis") ?? false { sports.append(.tennis) }
        if defaults?.bool(forKey: "shouldShowRacing") ?? false { sports.append(.racing) }

        // If no sports enabled, default to basketball
        if sports.isEmpty { sports.append(.basketball) }
        return sports
    }

    func handleNetworking(favoriteOnly: Bool, sport: SportSelection, targetDate: Date = Date(), hiddenLeagues: Set<String> = []) async -> ([Game], [Team]) {
        // watchOS: app group is not available cross-device, always use network
        #if os(watchOS)
        let snapshot: WidgetSnapshot? = nil
        #else
        let snapshot = WidgetDataStore.readSnapshot()
        #endif

        // Try the app group snapshot first — written by the main app, no network needed
        if let snapshot {
            AppLogger.widget.info("[networking] snapshot hit: \(snapshot.games.count) games, \(snapshot.teams.count) teams, age=\(Int(Date().timeIntervalSince(snapshot.updatedAt)))s, mem=\(widgetMemoryMB())")
            var games = applyLeagueFilter(
                filterSnapshot(snapshot.games, sport: sport, targetDate: targetDate),
                hiddenLeagues: hiddenLeagues
            )
            AppLogger.widget.info("[networking] after filter: \(games.count) games")
            let favorites = Favorites()

            if favoriteOnly {
                let favGames = games.filter { favorites.contains($0) }
                if !favGames.isEmpty {
                    AppLogger.widget.info("[networking] returning \(favGames.prefix(Self.maxDisplayGames).count) favorite games from snapshot")
                    return (Array(favGames.prefix(Self.maxDisplayGames)), snapshot.teams)
                }
            }

            games.sort { game1, game2 in
                let g1Fav = favorites.contains(game1)
                let g2Fav = favorites.contains(game2)
                if g1Fav && !g2Fav { return true }
                if !g1Fav && g2Fav { return false }
                return (game1.standardDate ?? .distantFuture) < (game2.standardDate ?? .distantFuture)
            }

            AppLogger.widget.info("[networking] returning \(min(games.count, Self.maxDisplayGames)) games from snapshot")
            return (Array(games.prefix(Self.maxDisplayGames)), snapshot.teams)
        }

        // Fallback: fetch from lightweight widget endpoint (games + teams in one request)
        AppLogger.widget.info("[networking] snapshot miss — falling back to network, mem=\(widgetMemoryMB())")
        do {
            let sportTypes = enabledSportTypes(for: sport)
            guard !sportTypes.isEmpty else {
                AppLogger.widget.warning("[networking] no sports enabled, returning empty")
                return ([], [])
            }

            let favorites = Favorites()
            // Fetch more games than needed so we can filter to the target day
            let fetchLimit = Self.maxDisplayGames * 5
            AppLogger.widget.info("[networking] fetching widget/schedule for \(sportTypes.map(\.rawValue).joined(separator: ",")) with \(favorites.teams.count) favorites, limit=\(fetchLimit), mem=\(widgetMemoryMB())")
            let (upcoming, teams) = try await NetworkHandler.getWidgetScheduleFor(
                sports: sportTypes,
                limit: fetchLimit,
                favorites: Array(favorites.teams)
            )
            AppLogger.widget.info("[networking] received \(upcoming.count) games, \(teams.count) teams, mem=\(widgetMemoryMB())")

            // Filter to target day only (same as snapshot path)
            var games = filterGamesToDay(upcoming, targetDate: targetDate)
            if let sportType = sport.sportType {
                games = games.filter { $0.sportType == sportType }
            }
            games = applyLeagueFilter(games, hiddenLeagues: hiddenLeagues)
            AppLogger.widget.info("[networking] after day filter: \(games.count) games for \(targetDate.formatted(.dateTime.month(.abbreviated).day()))")

            if favoriteOnly {
                let favGames = games.filter { favorites.contains($0) }
                if !favGames.isEmpty {
                    return (Array(favGames.prefix(Self.maxDisplayGames)), teams)
                }
            }

            return (Array(games.prefix(Self.maxDisplayGames)), teams)
        } catch {
            AppLogger.widget.error("[networking] fetch failed: \(error.localizedDescription), mem=\(widgetMemoryMB())")
            #if !os(watchOS)
            SentrySDK.capture(error: error)
            #endif
            return ([], [])
        }
    }

    /// Filters games to a single calendar day
    private func filterGamesToDay(_ games: [Game], targetDate: Date) -> [Game] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: targetDate)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return games.filter {
            guard let date = $0.standardDate else { return false }
            return date >= dayStart && date < dayEnd
        }
    }

    /// Filters the cached snapshot games by sport selection and target date (single day only)
    private func filterSnapshot(_ games: [Game], sport: SportSelection, targetDate: Date) -> [Game] {
        var filtered = filterGamesToDay(games, targetDate: targetDate)

        // If a specific sport is selected, filter to just that sport
        if let sportType = sport.sportType {
            filtered = filtered.filter { $0.sportType == sportType }
        }

        return filtered
    }

    private func isLiveGame(_ game: Game) -> Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty &&
               status != "ft" &&
               status != "aet" &&
               status != "not started" &&
               status != "ns" &&
               game.intHomeScore != nil &&
               game.intAwayScore != nil
    }
}
