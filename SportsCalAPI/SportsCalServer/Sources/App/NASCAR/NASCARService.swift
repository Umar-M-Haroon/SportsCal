//
//  NASCARService.swift
//
//  Fetching and caching for the NASCAR Cup Series (cf.nascar.com — public, no auth,
//  undocumented). Everything here is server-side and cached in Redis, so client load
//  never reaches NASCAR:
//
//  - Schedule: the season's race list plus each weekend's results, built into games by
//    ScheduleUpdateJob. A finished weekend never changes, so it is cached for good.
//  - Live: the live feed, polled by ESPNFetchJob (every minute, during a race weekend)
//    and LiveTicker (every 15s while a NASCAR session is live).
//  - Standings and per-race detail: on demand for the app, with short-lived caches.
//

import Foundation
import Vapor
import SportsCalModel

enum NASCARService {
    private static let logger = Logger(label: "com.sportscal.nascar")
    private static let base = "https://cf.nascar.com"
    /// Cup Series.
    static let series = 1

    // MARK: - Fetch

    static func fetch<T: Decodable>(_ type: T.Type, _ path: String, client: some Client) async throws -> T {
        let response = try await client.get(URI(string: base + path)) { req in
            req.headers.replaceOrAdd(name: .accept, value: "application/json")
            req.headers.replaceOrAdd(name: .userAgent, value: ESPNNetworking.userAgent)
        }
        guard response.status == .ok, let body = response.body else {
            throw Abort(.badGateway, reason: "NASCAR \(path) returned \(response.status.code)")
        }
        // Some NASCAR files start with a UTF-8 BOM, which JSONDecoder rejects.
        var data = Data(buffer: body)
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func raceList(season: Int, client: some Client) async throws -> [NASCARRace] {
        try await fetch(NASCARRaceListResponse.self, "/cacher/\(season)/race_list_basic.json", client: client).series1 ?? []
    }

    static func weekendFeed(season: Int, raceID: Int, client: some Client) async throws -> NASCARWeekendFeed {
        try await fetch(NASCARWeekendFeed.self, "/cacher/\(season)/\(series)/\(raceID)/weekend-feed.json", client: client)
    }

    static func liveFeed(client: some Client) async throws -> NASCARLiveFeed {
        try await fetch(NASCARLiveFeed.self, "/live/feeds/live-feed.json", client: client)
    }

    // MARK: - Redis keys

    private static func key(_ name: String, isDebug: Bool) -> String {
        (isDebug ? "debug-" : "") + name
    }

    static func raceListKey(isDebug: Bool) -> String { key("NASCAR Cup Races", isDebug: isDebug) }
    static func weekendKey(raceID: Int, isDebug: Bool) -> String { key("NASCAR Weekend \(raceID)", isDebug: isDebug) }
    static func standingsKey(isDebug: Bool) -> String { key("NASCAR Cup Standings", isDebug: isDebug) }
    static func raceDetailKey(raceID: Int, isDebug: Bool) -> String { key("NASCAR Race Detail \(raceID)", isDebug: isDebug) }

    /// Races for the schedule and the live path, cached between schedule rebuilds.
    struct CachedRace: Codable {
        let season: Int
        let race: NASCARRace
    }

    // MARK: - Schedule

    /// Every Cup race of the previous and current season as games. Throws only when the
    /// current season's race list can't be fetched, so the schedule job keeps the
    /// previous NASCAR games rather than dropping the series.
    static func scheduleGames(app: Application, isDebug: Bool, now: Date = Date()) async throws -> [Game] {
        let client = app.client
        let year = Calendar(identifier: .gregorian).component(.year, from: now)
        var races: [(season: Int, race: NASCARRace)] = []
        for season in [year - 1, year] {
            do {
                races += try await raceList(season: season, client: client).map { (season, $0) }
            } catch {
                logger.warning("NASCAR race list fetch failed", metadata: ["season": "\(season)", "error": "\(error)"])
                if season == year { throw error }
            }
        }
        await storeRaceList(races, app: app, isDebug: isDebug)

        let live = try? await liveFeed(client: client)
        // Weekend feeds for every race up to a week out: finished ones come from the
        // permanent cache after their first fetch.
        let horizon = now.addingTimeInterval(7 * 24 * 3600)
        let wanted = races.filter { entry in
            guard let start = NASCARGameBuilder.raceStartDate(race: entry.race, schedule: entry.race.schedule ?? []) else { return false }
            return start <= horizon
        }
        let weekends = await weekendFeeds(for: wanted.map { ($0.season, $0.race.raceID) }, app: app, isDebug: isDebug, now: now)

        let games = races.map { entry in
            NASCARGameBuilder.game(race: entry.race, weekend: weekends[entry.race.raceID], live: live, now: now,
                                   detail: isWeekendActive(entry.race, now: now) ? .live : .compact)
        }
        logger.info("NASCAR schedule built", metadata: [
            "races": "\(games.count)", "weekendFeeds": "\(weekends.count)"
        ])
        return games
    }

    /// Kept between schedule rebuilds so the live path can rebuild a game without
    /// refetching the 260KB race list every tick.
    private static func storeRaceList(_ races: [(season: Int, race: NASCARRace)], app: Application, isDebug: Bool) async {
        let cached = races.map { CachedRace(season: $0.season, race: $0.race) }
        try? await app.kv.setJSON(raceListKey(isDebug: isDebug), value: cached, ttl: 3 * 24 * 3600)
    }

    /// The race list as cached by the last schedule build.
    static func cachedRaces(app: Application, isDebug: Bool) async -> [(season: Int, race: NASCARRace)] {
        guard let cached = try? await app.kv.getJSON(raceListKey(isDebug: isDebug), as: [CachedRace].self) else { return [] }
        return cached.map { ($0.season, $0.race) }
    }

    /// Weekend feeds keyed by race ID. Finished weekends are cached permanently; others
    /// for five minutes, so the live path and the schedule rebuild share one fetch.
    static func weekendFeeds(for races: [(season: Int, raceID: Int)], app: Application, isDebug: Bool, now: Date = Date()) async -> [Int: NASCARWeekendFeed] {
        await withTaskGroup(of: (Int, NASCARWeekendFeed?).self) { group in
            var inFlight = 0
            var iterator = races.makeIterator()
            var result: [Int: NASCARWeekendFeed] = [:]
            func addNext() -> Bool {
                guard let (season, raceID) = iterator.next() else { return false }
                group.addTask { (raceID, await weekendFeed(season: season, raceID: raceID, app: app, isDebug: isDebug)) }
                return true
            }
            // At most six requests to NASCAR at once.
            while inFlight < 6, addNext() { inFlight += 1 }
            for await (raceID, feed) in group {
                if let feed { result[raceID] = feed }
                _ = addNext()
            }
            return result
        }
    }

    private static func weekendFeed(season: Int, raceID: Int, app: Application, isDebug: Bool) async -> NASCARWeekendFeed? {
        let key = weekendKey(raceID: raceID, isDebug: isDebug)
        if let cached = try? await app.kv.getString(key),
           let data = cached.data(using: .utf8),
           let feed = try? JSONDecoder().decode(NASCARWeekendFeed.self, from: data) {
            return feed
        }
        do {
            let response = try await app.client.get(URI(string: "\(base)/cacher/\(season)/\(series)/\(raceID)/weekend-feed.json")) { req in
                req.headers.replaceOrAdd(name: .userAgent, value: ESPNNetworking.userAgent)
            }
            guard response.status == .ok, let body = response.body else { return nil }
            let raw = String(buffer: body)
            let feed = try JSONDecoder().decode(NASCARWeekendFeed.self, from: Data(raw.utf8))
            if NASCARGameBuilder.finalResults(feed.race?.results) != nil {
                // Final results don't change; keep them for the season and a bit.
                try? await app.kv.setString(key, value: raw, ttl: 400 * 24 * 3600)
            } else {
                try? await app.kv.setString(key, value: raw, ttl: 5 * 60)
            }
            return feed
        } catch {
            logger.warning("NASCAR weekend feed fetch failed", metadata: ["race": "\(raceID)", "error": "\(error)"])
            return nil
        }
    }

    // MARK: - Live

    /// Games for every Cup weekend in progress (any session from 8h ago to 30min out),
    /// rebuilt from the live feed. Empty outside race weekends, without a network call.
    static func liveGames(app: Application, isDebug: Bool, now: Date = Date()) async -> [Game] {
        let races = await cachedRaces(app: app, isDebug: isDebug)
        let active = races.filter { isWeekendActive($0.race, now: now) }
        guard !active.isEmpty else { return [] }

        let live = try? await liveFeed(client: app.client)
        let weekends = await weekendFeeds(for: active.map { ($0.season, $0.race.raceID) }, app: app, isDebug: isDebug, now: now)
        return active.map { entry in
            NASCARGameBuilder.game(race: entry.race, weekend: weekends[entry.race.raceID], live: live, now: now, detail: .live)
        }
    }

    /// Whether any on-track session of this weekend falls between 8h ago and 30min ahead.
    static func isWeekendActive(_ race: NASCARRace, now: Date) -> Bool {
        let starts = (race.schedule ?? [])
            .filter { (1...3).contains($0.runType) }
            .compactMap { $0.startTimeUTC.flatMap(NASCARGameBuilder.utcDate) }
        let window = now.addingTimeInterval(-8 * 3600)...now.addingTimeInterval(30 * 60)
        if starts.contains(where: window.contains) { return true }
        // Between sessions of a weekend in progress (Saturday night before a Sunday race).
        guard let first = starts.min(), let last = starts.max() else { return false }
        return first <= now && now <= last
    }

    // MARK: - Standings / detail

    static func standings(app: Application, isDebug: Bool, now: Date = Date()) async throws -> NASCARStandings {
        let key = standingsKey(isDebug: isDebug)
        if let cached = try? await app.kv.getJSON(key, as: NASCARStandings.self) { return cached }
        let year = Calendar(identifier: .gregorian).component(.year, from: now)
        var rows: [NASCARPointsRow] = []
        var season = year
        for candidate in [year, year - 1] {
            rows = (try? await fetch([NASCARPointsRow].self, "/cacher/\(candidate)/\(series)/racinginsights-points-feed.json", client: app.client)) ?? []
            if !rows.isEmpty { season = candidate; break }
        }
        guard !rows.isEmpty else { throw Abort(.serviceUnavailable, reason: "NASCAR standings unavailable") }
        let standings = NASCARGameBuilder.standings(rows, season: season)
        try? await app.kv.setJSON(key, value: standings, ttl: 15 * 60)
        return standings
    }

    static func raceDetail(raceID: Int, app: Application, isDebug: Bool) async throws -> NASCARRaceDetail {
        let key = raceDetailKey(raceID: raceID, isDebug: isDebug)
        if let cached = try? await app.kv.getJSON(key, as: NASCARRaceDetail.self) { return cached }

        let races = await cachedRaces(app: app, isDebug: isDebug)
        guard let entry = races.first(where: { $0.race.raceID == raceID }) else {
            throw Abort(.notFound, reason: "Unknown NASCAR race \(raceID)")
        }
        let season = entry.season
        let client = app.client
        async let weekend = weekendFeeds(for: [(season, raceID)], app: app, isDebug: isDebug)[raceID]
        async let lapTimes = try? fetch(NASCARLapTimesFeed.self, "/cacher/\(season)/\(series)/\(raceID)/lap-times.json", client: client)
        async let notes = try? fetch(NASCARLapNotesFeed.self, "/cacher/\(season)/\(series)/\(raceID)/lap-notes.json", client: client)
        async let pits = try? fetch([NASCARPitRecord].self, "/cacher/live/series_\(series)/\(raceID)/live-pit-data.json", client: client)

        let weekendFeed = await weekend
        var detail = await NASCARGameBuilder.raceDetail(
            raceID: raceID, weekend: weekendFeed, lapTimes: lapTimes, notes: notes, pits: pits
        )
        // Full session results: the schedule copy of the game carries trimmed ones.
        detail.sessions = NASCARGameBuilder.game(race: entry.race, weekend: weekendFeed, live: nil, detail: .full).sessions
        // A finished race's detail is fixed; a live one moves every lap.
        let final = NASCARGameBuilder.finalResults(weekendFeed?.race?.results) != nil
        try? await app.kv.setJSON(key, value: detail, ttl: final ? 7 * 24 * 3600 : 30)
        return detail
    }
}
