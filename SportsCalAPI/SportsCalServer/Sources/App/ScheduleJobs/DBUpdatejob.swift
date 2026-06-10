//
//  DBUpdateJob.swift
//  
//
//  Created by Umar Haroon on 10/21/22.
//

import Foundation
import Queues
import RediStack
import SportsCalModel
import Logging
import Vapor

struct ScheduleUpdateJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.schedule-update")

    /// Extracts unique teams from games to ensure multi-season coverage
    func extractTeamsFromGames(_ games: [Game]) -> [Team] {
        var teamsDict: [String: Team] = [:]

        for game in games {
            // Extract home team
            if let idHomeTeam = game.idHomeTeam, !idHomeTeam.isEmpty {
                if teamsDict[idHomeTeam] == nil {
                    teamsDict[idHomeTeam] = Team(
                        idTeam: idHomeTeam,
                        strTeam: game.strHomeTeam,
                        strTeamShort: nil,
                        strAlternate: nil,
                        strTeamBadge: game.strHomeTeamBadge
                    )
                }
            }

            // Extract away team
            if let idAwayTeam = game.idAwayTeam, !idAwayTeam.isEmpty {
                if teamsDict[idAwayTeam] == nil {
                    teamsDict[idAwayTeam] = Team(
                        idTeam: idAwayTeam,
                        strTeam: game.strAwayTeam,
                        strTeamShort: nil,
                        strAlternate: nil,
                        strTeamBadge: game.strAwayTeamBadge
                    )
                }
            }
        }

        return Array(teamsDict.values)
    }

    /// Merges teams from API with teams extracted from games
    /// Prefers API teams (which have more complete data like strTeamShort)
    func mergeTeams(apiTeams: [Team], gameTeams: [Team]) -> [Team] {
        var mergedDict: [String: Team] = [:]

        // Add game teams first (as fallback)
        for team in gameTeams {
            if let idTeam = team.idTeam {
                mergedDict[idTeam] = team
            }
        }

        // Override with API teams (which have better data)
        for team in apiTeams {
            if let idTeam = team.idTeam {
                mergedDict[idTeam] = team
            }
        }

        return Array(mergedDict.values)
    }

    /// Counts total games across all sports in a LiveScore
    func countGames(in score: LiveScore) -> Int {
        [score.nba, score.mlb, score.soccer, score.nfl, score.nhl, score.golf, score.tennis, score.racing]
            .compactMap { $0?.events.count }
            .reduce(0, +)
    }

    /// Refresh schedules if missing, if the teams cache is empty, or if it's been
    /// more than 1 hour since the last update (or the timestamp is missing).
    static func shouldRefreshSchedules(hasSchedule: Bool, teamsCount: Int, lastUpdate: Date?, now: Date) -> Bool {
        guard hasSchedule, teamsCount > 0 else { return true }
        guard let lastUpdate else { return true }
        return now.timeIntervalSince(lastUpdate) / 3600 > 1
    }

    /// Normalizes a league's raw schedule events: dedupes games repeated across
    /// overlapping season fetches (previous/current/next), drops games with no
    /// timestamp, and backfills `isoDate` from `strTimestamp` where missing.
    static func normalizeLeagueEvents(_ events: [Game]) -> [Game] {
        var seenEventIDs = Set<String>()
        var normalized = events.filter { game in
            guard let eventID = game.idEvent else { return true }
            return seenEventIDs.insert(eventID).inserted
        }
        normalized.removeAll(where: { $0.strTimestamp == nil })
        return normalized.map {
            if $0.isoDate == nil {
                var game = $0
                game.isoDate = game.getDate()
                return game
            }
            return $0
        }
    }

    func run(context: Queues.QueueContext) async throws {
        let isDebug = context.application.environment == .development

        // Only fetch live scores if there are games happening or starting soon
        let shouldFetchLive = await Integrator.hasLiveOrUpcomingGames(
            redis: context.application.redis,
            isDebug: isDebug
        )

        if shouldFetchLive {
            Self.logger.info("Fetching TheSportsDB live scores")
            let liveResult = await Integrator.getAllLiveScores(context.application.client)
            try await context.application.redis.setex(RedisEndpoint.SportsDB.latestFullLiveInfo.getValue(isDebug: isDebug), toJSON: liveResult, expirationInSeconds: 60 * 30)
            try await context.application.redis.set(RedisEndpoint.SportsDB.latestLiveInfo.getValue(isDebug: isDebug), toJSON: liveResult)
            Self.logger.info("TheSportsDB live scores updated")
        } else {
            Self.logger.info("No live or upcoming games — skipping TheSportsDB live score fetch")
        }

        // Check if schedules already exist in Redis
        let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
        let teamsKey = RedisEndpoint.SportsDB.teams.getValue(isDebug: isDebug)
        let lastUpdateKey = RedisEndpoint.ESPN.scheduleLastUpdate.getValue(isDebug: isDebug)

        Self.logger.debug("Redis keys loaded", metadata: [
            "scheduleKey": "\(scheduleKey)",
            "teamsKey": "\(teamsKey)",
            "lastUpdateKey": "\(lastUpdateKey)"
        ])

        let existingSchedule = try await context.application.redis.get(scheduleKey, asJSON: LiveScore.self)
        let existingTeams = try await context.application.redis.get(teamsKey, asJSON: [Team].self)
        let lastUpdateTime = try await context.application.redis.get(lastUpdateKey, asJSON: Date.self)

        Self.logger.info("Cache status", metadata: [
            "scheduleExists": "\(existingSchedule != nil)",
            "teamsCount": "\(existingTeams?.count ?? 0)",
            "lastUpdate": "\(lastUpdateTime?.description ?? "never")"
        ])

        // Refresh schedules if missing or if it's been more than 1 hour
        let shouldRefreshSchedules = Self.shouldRefreshSchedules(
            hasSchedule: existingSchedule != nil,
            teamsCount: existingTeams?.count ?? 0,
            lastUpdate: lastUpdateTime,
            now: Date()
        )
        if shouldRefreshSchedules {
            Self.logger.info("Refreshing schedules from API", metadata: [
                "scheduleExists": "\(existingSchedule != nil)",
                "teamsCount": "\(existingTeams?.count ?? 0)",
                "lastUpdate": "\(lastUpdateTime?.description ?? "never")"
            ])
        } else {
            Self.logger.info("Using cached schedules", metadata: [
                "lastUpdate": "\(lastUpdateTime?.description ?? "never")"
            ])
        }

        if !shouldRefreshSchedules {
            Self.logger.info("Skipping schedule fetch — using cached data")
            return
        }

        Self.logger.info("Fetching schedules from API")
        var schedule: LiveScore = LiveScore(nba: nil, mlb: nil, soccer: nil, nfl: nil, nhl: nil, golf: nil, tennis: nil, racing: nil)
        var apiTeams: [Team] = []
        var allGames: [Game] = []

        for league in Leagues.allCases {
            do {
                // Skip ESPN-only leagues here — handled separately via ESPN below
                if league == .ncaaMBBTournament || league == .wnba { continue }

                if let response = try await SportsDBNetworking.getTeamInfoForLeague(app: context.application, DecodeType: Teams.self, league: league.rawValue) {
                    apiTeams.append(contentsOf: response.teams)
                }
                let response = try await SportsDBNetworking.getSchedule(app: context.application, DecodeType: LiveEvent.self, league: league.rawValue, singleYearSeason: league.sportsDBSingleYearSeason)
                    .compactMap({$0})
                var events = response
                    .reduce(into: LiveEvent(events: [])) { partialResult, next in
                    partialResult.events += next.events
                }
                events.events = Self.normalizeLeagueEvents(events.events)

                // Collect all games for team extraction
                allGames.append(contentsOf: events.events)

                switch league {
                case .nfl:
                    schedule.nfl = events
                    let newGames: [Game] = schedule.nfl?.events.map({ game in
                        if let date = game.getDate(), date.timeIntervalSinceNow > 0 {
                            // Only include essential fields - strSport/strLeague are computed from idLeague
                            // Deprecated fields removed: strPlayer, idPlayer, intEventScore, intEventScoreTotal, strEventTime, dateEvent, updated
                            let newGame = Game(idLiveScore: game.idLiveScore, idEvent: game.idEvent, strSport: nil, idLeague: game.idLeague, strLeague: nil, idHomeTeam: game.idHomeTeam, idAwayTeam: game.idAwayTeam, strHomeTeam: game.strHomeTeam, strAwayTeam: game.strAwayTeam, strHomeTeamBadge: game.strHomeTeamBadge, strAwayTeamBadge: game.strAwayTeamBadge, intHomeScore: nil, intAwayScore: nil, strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: game.strStatus, strProgress: game.strProgress, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: game.strTimestamp, isoDate: game.getDate())
                            return newGame
                        }
                        return game
                    }) ?? []
                    schedule.nfl?.events = newGames
                    Self.logger.info("Schedule loaded", metadata: ["sport": "nfl", "events": "\(events.events.count)"])
                case .nhl:
                    schedule.nhl = events
                    Self.logger.info("Schedule loaded", metadata: ["sport": "nhl", "events": "\(events.events.count)"])
                case .nba:
                    schedule.nba = events
                    Self.logger.info("Schedule loaded", metadata: ["sport": "nba", "events": "\(events.events.count)"])
                case .mlb:
                    schedule.mlb = events
                    Self.logger.info("Schedule loaded", metadata: ["sport": "mlb", "events": "\(events.events.count)"])
                case .pga:
                    schedule.golf = events
                    Self.logger.info("Schedule loaded", metadata: ["sport": "golf", "events": "\(events.events.count)"])
                case .atp, .wta:
                    // Tennis: build a STRUCTURED schedule from ESPN (event = tournament, with
                    // per-match round + draw) instead of TheSportsDB's flat, unstructured dump.
                    // ESPN `dates=<year>` returns the full season (~12MB/league/year), so gate
                    // the heavy fetch behind a 20-min staleness marker and reuse the cached
                    // parsed result on the frequent schedule runs. Both tours are handled once,
                    // on the .atp iteration; .wta is skipped.
                    if league == .wta { break }

                    let tennisKey = RedisEndpoint.ESPN.tennisSchedule.getValue(isDebug: isDebug)
                    let tennisLastUpdateKey = RedisEndpoint.ESPN.tennisScheduleLastUpdate.getValue(isDebug: isDebug)
                    var tennisEvent: LiveEvent?
                    if let lastUpdate = try? await context.application.redis.get(tennisLastUpdateKey, asJSON: Date.self),
                       Date().timeIntervalSince(lastUpdate) / 60 < 20,
                       let cached = try? await context.application.redis.get(tennisKey, asJSON: LiveEvent.self) {
                        tennisEvent = cached
                    } else {
                        let currentYear = Calendar.current.component(.year, from: Date())
                        var tennisGames: [Game] = []
                        for tour in [Leagues.atp, Leagues.wta] {
                            for year in [currentYear - 1, currentYear] {
                                if let scoreboard = try? await Integrator.getESPNScoreboard(for: tour, context.application.client, dates: year),
                                   let parsed = LiveEvent(events: scoreboard, league: tour) {
                                    tennisGames.append(contentsOf: parsed.events)
                                }
                            }
                        }
                        // Combined events (e.g. United Cup) appear in both the ATP and WTA
                        // feeds with identical competition IDs — dedupe by event id.
                        var seenTennisIDs = Set<String>()
                        tennisGames = tennisGames.filter { game in
                            guard let id = game.idEvent else { return true }
                            return seenTennisIDs.insert(id).inserted
                        }
                        if !tennisGames.isEmpty {
                            let built = LiveEvent(events: tennisGames)
                            tennisEvent = built
                            try? await context.application.redis.set(tennisKey, toJSON: built)
                            try? await context.application.redis.set(tennisLastUpdateKey, toJSON: Date())
                        }
                    }
                    // If the heavy ESPN fetch failed and the 20-min cache was stale, reuse the
                    // last good structured cache regardless of age before dropping to TheSportsDB.
                    // Otherwise a transient ESPN hiccup silently wipes every tournament name
                    // (browse regresses to two flat "ATP Tour"/"WTA Tour" buckets) until the next
                    // successful fetch — the named tournaments should be sticky once acquired.
                    var tennisSource = "espn"
                    if tennisEvent == nil,
                       let staleCache = try? await context.application.redis.get(tennisKey, asJSON: LiveEvent.self),
                       !staleCache.events.isEmpty {
                        tennisEvent = staleCache
                        tennisSource = "espn-stale-cache"
                    }
                    if let tennisEvent {
                        schedule.tennis = tennisEvent
                        Self.logger.info("Schedule loaded", metadata: ["sport": "tennis", "source": "\(tennisSource)", "events": "\(tennisEvent.events.count)"])
                    } else {
                        schedule.tennis = events // fallback to TheSportsDB if ESPN unavailable AND no cache
                        Self.logger.info("Schedule loaded", metadata: ["sport": "tennis", "source": "thesportsdb-fallback", "events": "\(events.events.count)"])
                    }
                case .formula1:
                    // TheSportsDB has event names but no results — fetch from ESPN for richer data
                    let currentYear = Calendar.current.component(.year, from: Date())
                    var espnScoreboards: [Scoreboard] = []
                    for year in [currentYear - 1, currentYear] {
                        if let scoreboard = try? await Integrator.getESPNScoreboard(for: .formula1, context.application.client, dates: year) {
                            espnScoreboards.append(scoreboard)
                        }
                    }
                    // Fetch constructor map from the first scoreboard that has race data
                    var f1ConstructorMap: [String: String] = [:]
                    for scoreboard in espnScoreboards {
                        let map = await ESPNNetworking.getF1ConstructorMap(req: context.application.client, scoreboard: scoreboard)
                        if !map.isEmpty {
                            f1ConstructorMap = map
                            break
                        }
                    }
                    // Fetch timing/gap data for all completed sessions
                    let f1TimingMap = await ESPNNetworking.getF1TimingMap(req: context.application.client, scoreboards: espnScoreboards)
                    var espnRacingGames: [Game] = []
                    for scoreboard in espnScoreboards {
                        if let liveEvent = LiveEvent(events: scoreboard, league: .formula1, constructorMap: f1ConstructorMap, timingMap: f1TimingMap) {
                            espnRacingGames.append(contentsOf: liveEvent.events)
                        }
                    }
                    if !espnRacingGames.isEmpty {
                        schedule.racing = LiveEvent(events: espnRacingGames)
                    } else {
                        schedule.racing = events // fallback to TheSportsDB
                    }
                    // Attach cached F1 enrichment data (circuits + standings)
                    if var racingGames = schedule.racing?.events {
                        let circuitsKey = RedisEndpoint.ESPN.f1Circuits.getValue(isDebug: isDebug)
                        let standingsKey = RedisEndpoint.ESPN.f1Standings.getValue(isDebug: isDebug)
                        let raceTimingKey = RedisEndpoint.ESPN.f1RaceTiming.getValue(isDebug: isDebug)
                        let cachedCircuits = try? await context.application.redis.get(circuitsKey, asJSON: [String: F1CircuitInfo].self)
                        let cachedStandings = try? await context.application.redis.get(standingsKey, asJSON: F1Standings.self)
                        let cachedRaceTiming = try? await context.application.redis.get(raceTimingKey, asJSON: F1RaceTiming.self)
                        if let circuits = cachedCircuits, !circuits.isEmpty {
                            for i in racingGames.indices {
                                let game = racingGames[i]
                                let raceName = game.strHomeTeam.lowercased().replacingOccurrences(of: "-", with: " ")
                                for (key, info) in circuits {
                                    let normalized = key.lowercased().replacingOccurrences(of: "-", with: " ")
                                    if raceName.contains(normalized) || normalized.contains(raceName) {
                                        racingGames[i] = Game(
                                            idLiveScore: game.idLiveScore, idEvent: game.idEvent,
                                            idLeague: game.idLeague,
                                            strHomeTeam: game.strHomeTeam, strAwayTeam: game.strAwayTeam,
                                            intHomeScore: game.intHomeScore, intAwayScore: game.intAwayScore,
                                            strStatus: game.strStatus, strProgress: game.strProgress,
                                            strTimestamp: game.strTimestamp, lastPlay: game.lastPlay,
                                            isCompleted: game.isCompleted, isoDate: game.isoDate,
                                            leaderboardEntries: game.leaderboardEntries,
                                            sessions: game.sessions, venueName: game.venueName,
                                            circuitInfo: info
                                        )
                                        break
                                    }
                                    if let venue = game.venueName?.lowercased(),
                                       (venue.contains(info.locality.lowercased()) || venue.contains(info.country.lowercased())) {
                                        racingGames[i] = Game(
                                            idLiveScore: game.idLiveScore, idEvent: game.idEvent,
                                            idLeague: game.idLeague,
                                            strHomeTeam: game.strHomeTeam, strAwayTeam: game.strAwayTeam,
                                            intHomeScore: game.intHomeScore, intAwayScore: game.intAwayScore,
                                            strStatus: game.strStatus, strProgress: game.strProgress,
                                            strTimestamp: game.strTimestamp, lastPlay: game.lastPlay,
                                            isCompleted: game.isCompleted, isoDate: game.isoDate,
                                            leaderboardEntries: game.leaderboardEntries,
                                            sessions: game.sessions, venueName: game.venueName,
                                            circuitInfo: info
                                        )
                                        break
                                    }
                                }
                            }
                            schedule.racing = LiveEvent(events: racingGames)
                        }
                        schedule.f1Standings = cachedStandings

                        // Attach cached race timing to the matching game (most recent race)
                        if let timing = cachedRaceTiming, var racingGames = schedule.racing?.events {
                            for i in racingGames.indices {
                                let game = racingGames[i]
                                let raceName = game.strHomeTeam.lowercased()
                                let venue = game.venueName?.lowercased() ?? ""
                                if let circuit = game.circuitInfo,
                                   raceName.contains(circuit.country.lowercased())
                                    || raceName.contains(circuit.locality.lowercased())
                                    || venue.contains(circuit.country.lowercased())
                                    || venue.contains(circuit.locality.lowercased()) {
                                    racingGames[i] = Game(
                                        idLiveScore: game.idLiveScore, idEvent: game.idEvent,
                                        idLeague: game.idLeague,
                                        strHomeTeam: game.strHomeTeam, strAwayTeam: game.strAwayTeam,
                                        intHomeScore: game.intHomeScore, intAwayScore: game.intAwayScore,
                                        strStatus: game.strStatus, strProgress: game.strProgress,
                                        strTimestamp: game.strTimestamp, lastPlay: game.lastPlay,
                                        isCompleted: game.isCompleted, isoDate: game.isoDate,
                                        leaderboardEntries: game.leaderboardEntries,
                                        sessions: game.sessions, venueName: game.venueName,
                                        circuitInfo: game.circuitInfo,
                                        raceTiming: timing
                                    )
                                    break
                                }
                            }
                            schedule.racing = LiveEvent(events: racingGames)
                        }
                    }
                    Self.logger.info("Schedule loaded", metadata: ["sport": "racing", "events": "\(schedule.racing?.events.count ?? 0)", "constructors": "\(f1ConstructorMap.count)", "timingCompetitions": "\(f1TimingMap.count)"])
                default:
                    if schedule.soccer == nil {
                        schedule.soccer = events
                    } else {
                        schedule.soccer?.events += events.events
                    }
                }
            } catch {
                Self.logger.error("Failed to fetch league schedule", metadata: [
                    "league": "\(league)",
                    "leagueID": "\(league.rawValue)",
                    "error": "\(error)"
                ])
            }
        }

        // Fetch NCAA Tournament games (ESPN-only, no TheSportsDB)
        do {
            if let scoreboard = try await Integrator.getESPNScoreboard(for: .ncaaMBBTournament, context.application.client) as Scoreboard? {
                if let liveEvent = LiveEvent(events: scoreboard, league: .ncaaMBBTournament) {
                    if schedule.nba == nil {
                        schedule.nba = liveEvent
                    } else {
                        schedule.nba?.events += liveEvent.events
                    }
                    allGames.append(contentsOf: liveEvent.events)
                    Self.logger.info("NCAA Tournament schedule loaded", metadata: ["events": "\(liveEvent.events.count)"])
                }
            }
        } catch {
            Self.logger.warning("NCAA Tournament schedule fetch failed: \(error)")
        }

        // Fetch WNBA games (ESPN-only, no TheSportsDB)
        do {
            if let scoreboard = try await Integrator.getESPNScoreboard(for: .wnba, context.application.client) as Scoreboard? {
                if let liveEvent = LiveEvent(events: scoreboard, league: .wnba) {
                    if schedule.nba == nil {
                        schedule.nba = liveEvent
                    } else {
                        schedule.nba?.events += liveEvent.events
                    }
                    allGames.append(contentsOf: liveEvent.events)
                    Self.logger.info("WNBA schedule loaded", metadata: ["events": "\(liveEvent.events.count)"])
                }
            }
        } catch {
            Self.logger.warning("WNBA schedule fetch failed: \(error)")
        }

        // Enrich schedule with ESPN scoreboard data (records, leaders, linescores, venue, etc.)
        Self.logger.info("Enriching schedule with ESPN scoreboard data")
        schedule = await enrichScheduleWithESPN(schedule: schedule, client: context.application.client)

        // Re-attach cached injuries (InjuriesEnrichmentJob persists the lookup dict
        // but the schedule is rebuilt from scratch here, which would drop per-Game fields)
        let injuriesKey = RedisEndpoint.ESPN.injuries.getValue(isDebug: isDebug)
        if let cachedInjuries = try? await context.application.redis.get(injuriesKey, asJSON: [String: [InjuryReport]].self),
           !cachedInjuries.isEmpty {
            InjuriesEnrichmentJob.applyInjuries(to: &schedule, lookup: cachedInjuries)
        }

        // Extract teams from all games (multi-season coverage)
        let gameTeams = extractTeamsFromGames(allGames)
        let mergedTeams = mergeTeams(apiTeams: apiTeams, gameTeams: gameTeams)
        Self.logger.info("Teams extracted and merged", metadata: [
            "fromGames": "\(gameTeams.count)",
            "fromAPI": "\(apiTeams.count)",
            "totalMerged": "\(mergedTeams.count)",
            "totalGames": "\(allGames.count)"
        ])

        // Compare with existing cache — only write to Redis if data actually changed
        let scheduleChanged = (existingSchedule != schedule)
        let newGameCount = countGames(in: schedule)
        let oldGameCount = existingSchedule.map { countGames(in: $0) } ?? 0

        if scheduleChanged {
            try await context.application.redis.set(scheduleKey, toJSON: schedule)
            try await context.application.redis.set(RedisEndpoint.SportsDB.teams.getValue(isDebug: isDebug), toJSON: mergedTeams)
            Self.logger.info("Schedules updated — new data detected", metadata: [
                "oldGameCount": "\(oldGameCount)",
                "newGameCount": "\(newGameCount)"
            ])
        } else {
            Self.logger.info("Schedules unchanged — no new data from API", metadata: [
                "gameCount": "\(newGameCount)"
            ])
        }

        // Seed the final "Teams" key if it doesn't exist yet (before ESPNTeamFetchJob runs)
        let finalTeamsKey = RedisEndpoint.teams.getValue(isDebug: isDebug)
        let existingFinalTeams = try await context.application.redis.get(finalTeamsKey, asJSON: [Team].self)
        if existingFinalTeams == nil || existingFinalTeams?.isEmpty == true {
            try await context.application.redis.set(finalTeamsKey, toJSON: mergedTeams)
            Self.logger.info("Seeded Teams endpoint", metadata: ["teamsCount": "\(mergedTeams.count)"])
        }

        // Always update the timestamp so we know when we last checked
        try await context.application.redis.set(lastUpdateKey, toJSON: Date())
        Self.logger.info("Schedule check complete", metadata: ["dataChanged": "\(scheduleChanged)"])
    }
    // MARK: - ESPN Enrichment

    /// Fetches ESPN scoreboards for each sport and merges enrichment data
    /// (records, leaders, linescores, venue, team colors) into the TheSportsDB schedule.
    private func enrichScheduleWithESPN(schedule: LiveScore, client: any Client) async -> LiveScore {
        let sportLeagues: [(SportType, Leagues, WritableKeyPath<LiveScore, LiveEvent?>)] = [
            (.basketball, .nba, \.nba),
            (.mlb, .mlb, \.mlb),
            (.nfl, .nfl, \.nfl),
            (.hockey, .nhl, \.nhl),
        ]

        var enriched = schedule

        for (sport, league, keyPath) in sportLeagues {
            guard let scheduleEvents = schedule[keyPath: keyPath] else { continue }
            do {
                let scoreboard = try await Integrator.getESPNScoreboard(for: league, client)
                guard let espnLiveEvent = LiveEvent(events: scoreboard, league: league) else { continue }

                let merged = mergeEnrichment(schedule: scheduleEvents, espn: espnLiveEvent)
                enriched[keyPath: keyPath] = merged
                Self.logger.info("ESPN enrichment merged", metadata: ["sport": "\(sport)", "espnGames": "\(espnLiveEvent.events.count)", "scheduleGames": "\(scheduleEvents.events.count)"])
            } catch {
                Self.logger.warning("ESPN enrichment failed for \(sport): \(error)")
            }
        }

        // Soccer enrichment from cached scoreboards (already fetched by ESPNSoccerJob)
        // Tennis/Golf/Racing already use ESPN as primary source in schedule build

        return enriched
    }

    /// Normalizes team names to handle abbreviation differences
    /// (e.g., "LA Clippers" → "los angeles clippers")
    func normalizeTeamName(_ name: String) -> String {
        var result = name.lowercased()
        let abbreviations: [(abbreviation: String, full: String)] = [
            ("la ", "los angeles "),
            ("ny ", "new york "),
            ("nyc ", "new york city "),
            ("nyrb", "new york red bulls"),
            ("okc ", "oklahoma city "),
            ("phx ", "phoenix "),
            ("gs ", "golden state "),
            ("no ", "new orleans "),
            ("sa ", "san antonio "),
            ("sl ", "salt lake "),
            ("stl ", "st. louis "),
            ("kc ", "kansas city "),
            ("tb ", "tampa bay "),
            ("ne ", "new england "),
            ("mn ", "minnesota "),
            ("ind ", "indiana "),
        ]
        for (abbr, full) in abbreviations {
            if result.hasPrefix(abbr) {
                result = full + result.dropFirst(abbr.count)
                break
            }
        }
        result = result.replacingOccurrences(of: " fc", with: "")
        result = result.replacingOccurrences(of: "fc ", with: "")
        result = result.replacingOccurrences(of: " sc", with: "")
        result = result.replacingOccurrences(of: "sc ", with: "")
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Merges ESPN enrichment fields into TheSportsDB schedule games by matching team names + day.
    func mergeEnrichment(schedule: LiveEvent, espn: LiveEvent) -> LiveEvent {
        // Build ESPN lookup by team names + day
        var espnByNames: [String: Game] = [:]
        var espnByNormalized: [String: Game] = [:]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)

        for game in espn.events {
            let day: String
            if let date = game.isoDate {
                day = df.string(from: date)
            } else if let ts = game.strTimestamp, ts.count >= 10 {
                day = String(ts.prefix(10))
            } else {
                day = ""
            }
            let key = "\(game.strHomeTeam.lowercased())|\(game.strAwayTeam.lowercased())|\(day)"
            espnByNames[key] = game

            let normalizedKey = "\(normalizeTeamName(game.strHomeTeam))|\(normalizeTeamName(game.strAwayTeam))|\(day)"
            espnByNormalized[normalizedKey] = game

            // Also index by team ID for better matching
            if let homeID = game.idHomeTeam, let awayID = game.idAwayTeam {
                let idKey = "\(homeID)|\(awayID)|\(day)"
                espnByNames[idKey] = game
            }
        }

        let merged = schedule.events.map { scheduleGame -> Game in
            let day: String
            if let date = scheduleGame.isoDate {
                day = df.string(from: date)
            } else if let ts = scheduleGame.strTimestamp, ts.count >= 10 {
                day = String(ts.prefix(10))
            } else {
                day = ""
            }

            // Try matching by team names
            let nameKey = "\(scheduleGame.strHomeTeam.lowercased())|\(scheduleGame.strAwayTeam.lowercased())|\(day)"
            var espnMatch = espnByNames[nameKey]

            // Try matching by team IDs
            if espnMatch == nil, let homeID = scheduleGame.idHomeTeam, let awayID = scheduleGame.idAwayTeam {
                let idKey = "\(homeID)|\(awayID)|\(day)"
                espnMatch = espnByNames[idKey]
            }

            // Fallback: normalized team names (handles "LA" vs "Los Angeles" etc.)
            if espnMatch == nil {
                let normalizedKey = "\(normalizeTeamName(scheduleGame.strHomeTeam))|\(normalizeTeamName(scheduleGame.strAwayTeam))|\(day)"
                espnMatch = espnByNormalized[normalizedKey]
            }

            guard let espnGame = espnMatch else { return scheduleGame }

            // Merge ESPN enrichment fields onto schedule game
            let isPreGame = espnGame.strStatus == "pre"
            return Game(
                idLiveScore: scheduleGame.idLiveScore,
                idEvent: scheduleGame.idEvent,
                idLeague: scheduleGame.idLeague,
                idHomeTeam: scheduleGame.idHomeTeam,
                idAwayTeam: scheduleGame.idAwayTeam,
                strHomeTeam: espnGame.strHomeTeam,
                strAwayTeam: espnGame.strAwayTeam,
                strHomeTeamBadge: espnGame.strHomeTeamBadge ?? scheduleGame.strHomeTeamBadge,
                strAwayTeamBadge: espnGame.strAwayTeamBadge ?? scheduleGame.strAwayTeamBadge,
                intHomeScore: isPreGame ? scheduleGame.intHomeScore : (espnGame.intHomeScore ?? scheduleGame.intHomeScore),
                intAwayScore: isPreGame ? scheduleGame.intAwayScore : (espnGame.intAwayScore ?? scheduleGame.intAwayScore),
                strStatus: espnGame.strStatus ?? scheduleGame.strStatus,
                strProgress: espnGame.strProgress ?? scheduleGame.strProgress,
                strTimestamp: scheduleGame.strTimestamp,
                lastPlay: espnGame.lastPlay ?? scheduleGame.lastPlay,
                homeLinescores: espnGame.homeLinescores ?? scheduleGame.homeLinescores,
                awayLinescores: espnGame.awayLinescores ?? scheduleGame.awayLinescores,
                homeLeaders: espnGame.homeLeaders ?? scheduleGame.homeLeaders,
                awayLeaders: espnGame.awayLeaders ?? scheduleGame.awayLeaders,
                isCompleted: espnGame.isCompleted ?? scheduleGame.isCompleted,
                isoDate: scheduleGame.isoDate,
                venueName: espnGame.venueName ?? scheduleGame.venueName,
                homeTeamColor: espnGame.homeTeamColor ?? scheduleGame.homeTeamColor,
                awayTeamColor: espnGame.awayTeamColor ?? scheduleGame.awayTeamColor,
                homeRecord: espnGame.homeRecord ?? scheduleGame.homeRecord,
                awayRecord: espnGame.awayRecord ?? scheduleGame.awayRecord,
                homeSeed: espnGame.homeSeed ?? scheduleGame.homeSeed,
                awaySeed: espnGame.awaySeed ?? scheduleGame.awaySeed,
                playoff: espnGame.playoff ?? scheduleGame.playoff
            )
        }

        return LiveEvent(events: merged)
    }
}

class DateFormatters {
    static let isoFormatter = ISO8601DateFormatter()
    static let dateFormatter = DateFormatter()
    static let backupISOFormatter = DateFormatter()
}
