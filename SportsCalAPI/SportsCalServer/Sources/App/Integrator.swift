//
//  Integrator.swift
//  
//
//  Created by Umar Haroon on 2/27/23.
//

import Foundation
import Vapor
import Redis
import SportsCalModel
import Logging

/// Process-wide memo for `Integrator.activeLeagues`, keyed by environment.
///
/// The computation behind it is expensive out of all proportion to how often its
/// answer changes: two multi-MB Redis reads, two full JSON decodes, and a walk over
/// every scheduled event — to produce a set of at most ~50 league cases that turns
/// over on the hour. Callers on the hot path (the `/ws` push loop, once per client
/// per 2s) were paying that in full.
///
/// Stale-while-revalidate: once a value exists, a caller arriving during another
/// caller's refresh gets the previous one immediately rather than queueing behind
/// the Redis round-trip. Actor reentrancy across the awaited fetch is what lets
/// them in, and `refreshing` is what stops them all from starting their own.
/// Throttles the secondary golf tour scoreboards. Five extra ESPN calls per live tick
/// would be waste — a leaderboard moves over minutes, not seconds — so the result is
/// reused for `ttl`, matching the PGA fetch's own throttle.
actor GolfTourCache {
    static let shared = GolfTourCache()
    static let ttl: TimeInterval = 5 * 60

    private var games: [Game] = []
    private var tours: Set<Leagues> = []
    private var fetchedAt: Date?

    func current(for requested: [Leagues]) -> [Game]? {
        guard let fetchedAt, Date().timeIntervalSince(fetchedAt) < Self.ttl,
              tours == Set(requested) else { return nil }
        return games
    }

    func store(_ games: [Game], for tours: [Leagues]) {
        self.games = games
        self.tours = Set(tours)
        self.fetchedAt = Date()
    }
}

actor ActiveLeaguesCache {
    static let shared = ActiveLeaguesCache()

    /// Long enough that a busy evening's WS traffic collapses to a trickle of
    /// recomputations, short enough that a league tipping into its window is picked
    /// up well before its first event starts.
    static let ttl: TimeInterval = 30

    private struct Entry {
        /// nil is a real answer here — "cold start, treat every league as active" —
        /// so it's stored inside the entry rather than signalled by its absence.
        var value: Set<Leagues>?
        var fetchedAt: Date
    }

    private var entries: [Bool: Entry] = [:]
    /// The refresh currently in flight, so concurrent callers join it rather than each
    /// starting their own.
    private var inFlight: [Bool: Task<Set<Leagues>?, Never>] = [:]

    func current(isDebug: Bool, fetch: @escaping @Sendable () async -> Set<Leagues>?) async -> Set<Leagues>? {
        let existing = entries[isDebug]
        if let existing, Date().timeIntervalSince(existing.fetchedAt) < Self.ttl {
            return existing.value
        }

        // Stale value plus a refresh already running: serve the stale one and don't wait.
        if let existing, inFlight[isDebug] != nil {
            return existing.value
        }

        // Nothing to serve. Everyone here must wait — but on *one* fetch, not one each.
        // Process start is exactly when every `/ws` client reconnects at once, so a
        // stampede here would put N concurrent multi-MB Redis reads and JSON decodes on
        // the box at the worst possible moment — the July 2026 pool-exhaustion pattern
        // this cache exists to prevent.
        if let running = inFlight[isDebug] {
            return await running.value
        }

        let task = Task { await fetch() }
        inFlight[isDebug] = task
        let value = await task.value
        inFlight[isDebug] = nil
        // Stamped unconditionally: a Redis blip returning nil shouldn't turn every
        // subsequent tick into another attempt.
        entries[isDebug] = Entry(value: value, fetchedAt: Date())
        return value
    }

    /// Drops the memo so the next read recomputes. For tests, and for any future
    /// caller that has just written a new schedule and wants it reflected at once.
    func invalidate() {
        entries.removeAll()
    }
}

class Integrator {
    private static let logger = Logger(label: "com.sportscal.integrator")
    static func getAllLiveScores(_ client: some Client) async -> LiveScore {
        let leagues = Leagues.allCases

        func fetchSport(_ scoreType: SportsDBNetworking.LiveScoreType) async -> LiveEvent? {
            do {
                return try await SportsDBNetworking.callLiveScore(req: client, DecodeType: LiveEvent.self, scoreType: scoreType)
            } catch {
                logger.error("TheSportsDB live score failed for sport, continuing with others", metadata: [
                    "sport": "\(scoreType.rawValue)",
                    "error": "\(error)"
                ])
                return nil
            }
        }

        let basketball = await fetchSport(.basketball)
        var soccer = await fetchSport(.soccer)
        let filteredSoccer = soccer?.events.filter({ game in
            leagues.contains(where: {
                $0.rawValue == Int(game.idLeague ?? "")
            })
        }) ?? []
        soccer?.events = filteredSoccer
        let hockey = await fetchSport(.hockey)
        let mlb = await fetchSport(.mlb)
        let nfl = await fetchSport(.nfl)
        let golf = await fetchSport(.golf)
        let tennis = await fetchSport(.tennis)
        let racing = await fetchSport(.motorsport)
        var result = LiveScore(nba: basketball, mlb: mlb, soccer: soccer, nfl: nfl, nhl: hockey, golf: golf, tennis: tennis, racing: racing)
        result.removeOtherInfo()
        result.removeNonStarting()
        return result
    }
    
    /// Last time golf scoreboard was fetched — used to throttle golf to every 5 minutes
    private static var lastGolfFetch: Date?
    private static var lastGolfResult: Scoreboard?
    private static let golfFetchInterval: TimeInterval = 5 * 60 // 5 minutes

    private static func getESPNScores(_ client: some Client, activeLeagues: Set<Leagues>? = nil) async -> [SportType: Scoreboard] {
        return await withTaskGroup(of: (SportType, Scoreboard?).self) { group in
            var espnInfo: [SportType: Scoreboard] = [:]
            for sport in SportType.allCases.filter({$0.toLeague != nil}) {
                // Skip sports whose mapped league isn't in the active set (nil = fetch all).
                if let activeLeagues, let mapped = sport.toLeague, !activeLeagues.contains(mapped) {
                    continue
                }
                // Throttle golf fetches — every 5 min instead of every minute
                if sport == .golf,
                   let lastFetch = lastGolfFetch,
                   Date().timeIntervalSince(lastFetch) < golfFetchInterval,
                   let cached = lastGolfResult {
                    espnInfo[sport] = cached
                    logger.info("Using cached golf scoreboard", metadata: [
                        "age": "\(String(format: "%.0f", Date().timeIntervalSince(lastFetch)))s"
                    ])
                    continue
                }
                group.addTask {
                    do {
                        let result = try await getScoreboard(sport: sport, client: client)
                        if sport == .golf {
                            await updateGolfCache(result)
                        }
                        return (sport, result)
                    } catch {
                        logger.error("ESPN fetch failed for sport, continuing with others", metadata: [
                            "sport": "\(sport)",
                            "error": "\(error)"
                        ])
                        return (sport, nil)
                    }
                }
            }
            for await (sport, scoreboard) in group {
                if let scoreboard {
                    espnInfo[sport] = scoreboard
                }
            }
            return espnInfo
        }
    }
    
    private static func updateGolfCache(_ scoreboard: Scoreboard) {
        lastGolfFetch = Date()
        lastGolfResult = scoreboard
    }

    public static func getESPNScoreboard(for league: Leagues, _ client: some Client, dates: Int? = nil) async throws -> Scoreboard {
        try await ESPNNetworking.getScoreboard(req: client, DecodeType: Scoreboard.self, league: league, dates: dates)
    }
    
    static func getESPNLiveScore(_ client: some Client, f1ConstructorMap: [String: String] = [:], activeLeagues: Set<Leagues>? = nil) async -> LiveScore {
        let espnScores = await getESPNScores(client, activeLeagues: activeLeagues)
        var events: [SportType: LiveEvent] = [:]
        for (sportType, scoreboard) in espnScores {
            if let league = sportType.toLeague {
                if league.isRacing {
                    // For F1, pass the cached constructor map so live data has team names
                    var constructorMap = f1ConstructorMap
                    // If no cached map, try to fetch one quickly from this scoreboard
                    if constructorMap.isEmpty {
                        constructorMap = await ESPNNetworking.getF1ConstructorMap(req: client, scoreboard: scoreboard)
                    }
                    // Fetch live timing for in-progress sessions
                    let timingMap = await ESPNNetworking.getF1TimingMap(req: client, scoreboards: [scoreboard])
                    events[sportType] = LiveEvent(events: scoreboard, league: league, constructorMap: constructorMap, timingMap: timingMap)
                } else {
                    events[sportType] = LiveEvent(events: scoreboard, league: league)
                }
            }
        }
        // Golf beyond the PGA TOUR: ESPN serves each tour on its own scoreboard, and they
        // all belong in the single `golf` bucket — each game carries its own `idLeague`.
        let extraGolf = await getExtraGolfLiveEvents(client, activeLeagues: activeLeagues)
        if !extraGolf.isEmpty {
            if events[.golf] == nil {
                events[.golf] = LiveEvent(events: extraGolf)
            } else {
                events[.golf]?.events += extraGolf
            }
        }
        return LiveScore(nba: events[.basketball], mlb: events[.mlb], nfl: events[.nfl], nhl: events[.hockey], golf: events[.golf], tennis: events[.tennis], racing: events[.racing])
    }

    /// Golf tours that only exist on ESPN (the PGA TOUR comes through the main
    /// SportType-keyed path, which allows one league per sport).
    static let secondaryGolfTours: [Leagues] = [.dpWorld, .livGolf, .lpga, .championsTour, .kornFerry]

    /// Live events for every secondary golf tour that's currently active. Throttled
    /// alongside the PGA fetch, since golf leaderboards move slowly.
    private static func getExtraGolfLiveEvents(_ client: some Client, activeLeagues: Set<Leagues>?) async -> [Game] {
        let tours = secondaryGolfTours.filter { activeLeagues?.contains($0) ?? true }
        guard !tours.isEmpty else { return [] }
        if let cached = await GolfTourCache.shared.current(for: tours) { return cached }

        let games = await withTaskGroup(of: [Game].self) { group in
            for tour in tours {
                group.addTask {
                    do {
                        let scoreboard = try await getESPNScoreboard(for: tour, client)
                        return LiveEvent(events: scoreboard, league: tour)?.events ?? []
                    } catch {
                        logger.error("ESPN golf tour fetch failed", metadata: [
                            "tour": "\(tour)", "error": "\(error)"
                        ])
                        return []
                    }
                }
            }
            var all: [Game] = []
            for await events in group { all += events }
            return all
        }
        await GolfTourCache.shared.store(games, for: tours)
        return games
    }
    
    /// How long past its final day marker a multi-day event still counts as live: 7h to
    /// land the marker inside its own day, plus the day itself.
    static let multiDayEventTail: TimeInterval = 31 * 60 * 60

    /// Default live-fetch window: started in the last 8h OR starting in the next 30min.
    static let defaultLiveWindow: ClosedRange<TimeInterval> = -(8 * 60 * 60)...(30 * 60)

    /// Union of leagues with at least one event falling inside `window`, considering both
    /// the TSDB-sourced `Latest Schedule` and the ESPN-sourced `ESPN Schedule Window`.
    /// Returns nil when both sources are missing — callers should treat nil as "cold start,
    /// fetch everything" rather than "nothing is happening".
    static func activeLeagues(
        redis: RedisClient,
        isDebug: Bool,
        window: ClosedRange<TimeInterval> = defaultLiveWindow,
        now: Date = Date()
    ) async -> Set<Leagues>? {
        let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
        let windowKey = RedisEndpoint.ESPN.espnScheduleWindow.getValue(isDebug: isDebug)

        let schedule = try? await redis.get(scheduleKey, asJSON: LiveScore.self)
        let espnWindow = try? await redis.get(windowKey, asJSON: [Leagues: Scoreboard].self)

        if schedule == nil && espnWindow == nil {
            logger.info("No schedule or ESPN window in Redis (cold start?) — treating all leagues as active")
            return nil
        }

        var active: Set<Leagues> = []

        // TSDB schedule: one game-list per sport, each event carries its own idLeague.
        if let schedule {
            let allEvents = [schedule.nba, schedule.mlb, schedule.soccer, schedule.nfl, schedule.nhl, schedule.golf, schedule.tennis, schedule.racing]
                .compactMap { $0 }
                .flatMap { $0.events }
            for game in allEvents {
                guard let gameDate = game.isoDate ?? game.getDate() else { continue }
                guard let idLeague = game.idLeague, let leagueID = Int(idLeague),
                      let league = Leagues(rawValue: leagueID) else { continue }
                if let end = game.endDateParsed, end > gameDate {
                    // A golf tournament runs Thursday to Sunday. Judging it by its start
                    // alone made the league active on Thursday only, so Friday's round
                    // never refreshed. Its dates are day markers (midnight ET), hence the
                    // shift through the final day.
                    let started = gameDate.timeIntervalSince(now) <= window.upperBound
                    let over = end.addingTimeInterval(multiDayEventTail).timeIntervalSince(now) < 0
                    if started && !over { active.insert(league) }
                    continue
                }
                let offset = gameDate.timeIntervalSince(now)
                guard window.contains(offset) else { continue }
                active.insert(league)
            }
        }

        // ESPN window: one scoreboard per league, event.date is "yyyy-MM-dd'T'HH:mm'Z'".
        if let espnWindow {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
            formatter.timeZone = .init(secondsFromGMT: 0)
            for (league, scoreboard) in espnWindow {
                let hasEvent = scoreboard.events.contains { event in
                    guard let eventDate = formatter.date(from: event.date) else { return false }
                    // Same as above: a golf tournament runs for days, so judging it by its
                    // start alone stops refreshing it after the first round.
                    if let endString = event.endDate, let end = formatter.date(from: endString), end > eventDate {
                        return eventDate.timeIntervalSince(now) <= window.upperBound
                            && end.addingTimeInterval(multiDayEventTail).timeIntervalSince(now) >= 0
                    }
                    return window.contains(eventDate.timeIntervalSince(now))
                }
                if hasEvent { active.insert(league) }
            }
        }

        return active
    }

    /// Cached `activeLeagues` for the default window — one recomputation per
    /// `ActiveLeaguesCache.ttl` process-wide, no matter how many callers ask.
    ///
    /// The uncached form reads *and JSON-decodes* two multi-MB Redis blobs and walks
    /// every event in them. The `/ws` loop called it once per connected client per 2s
    /// tick, so cost scaled with client count on exactly the busy evenings that wedged
    /// the Redis pool (July 2026). Four minutely jobs call it too. League activity
    /// turns over on the hour, not the second, so a short TTL costs nothing in
    /// correctness — a league becoming active is picked up within `ttl`, and the
    /// window itself already spans 8h back / 30min forward.
    static func activeLeaguesCached(redis: RedisClient, isDebug: Bool) async -> Set<Leagues>? {
        await ActiveLeaguesCache.shared.current(isDebug: isDebug) {
            await activeLeagues(redis: redis, isDebug: isDebug)
        }
    }

    /// Back-compat wrapper. Cold-start (nil activeLeagues) → true; otherwise true iff any
    /// league is active.
    static func hasLiveOrUpcomingGames(redis: RedisClient, isDebug: Bool) async -> Bool {
        guard let active = await activeLeaguesCached(redis: redis, isDebug: isDebug) else { return true }
        return !active.isEmpty
    }

    static func getTeam(league: Leagues, client: some Client) async throws -> TeamResponse {
        try await ESPNNetworking.getTeam(req: client, DecodeType: TeamResponse.self, league: league)
    }

    static func getScoreboard(sport: SportType, client: Client) async throws -> Scoreboard {
        try await ESPNNetworking.getScoreboard(req: client, DecodeType: Scoreboard.self, scoreType: sport)
    }
}

extension SportType {
    public var toLeague: Leagues? {
        switch self {
        case .basketball:
            return .nba
        case .soccer:
            return nil
        case .hockey:
            return .nhl
        case .mlb:
            return .mlb
        case .nfl:
            return .nfl
        case .golf:
            return .pga
        case .tennis:
            return nil
        case .racing:
            return .formula1
        }
    }
}
