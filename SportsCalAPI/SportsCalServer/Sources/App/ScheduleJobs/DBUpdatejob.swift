//
//  DBUpdateJob.swift
//  
//
//  Created by Umar Haroon on 10/21/22.
//

import Foundation
import Queues
@preconcurrency import RediStack
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

    /// The tennis build fetches TWO ESPN seasons (tournaments straddle New Year), so
    /// the feed can hold two editions of the same tournament — and Browse groups by
    /// `tournamentName`, which merged 2025 and 2026 Wimbledon into one mixed bucket
    /// (last year's finished matches and "TBD" doubles beside this year's draw).
    /// Past editions stay in the feed for history, but get the season year suffixed
    /// onto their name ("Wimbledon 2025") so each edition browses separately.
    /// December events count toward the NEXT season (the United Cup straddles New
    /// Year) so a single edition never splits across the boundary.
    static func disambiguateTennisSeasons(_ games: [Game], now: Date = Date()) -> [Game] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        func season(of date: Date) -> Int {
            let year = utc.component(.year, from: date)
            return utc.component(.month, from: date) == 12 ? year + 1 : year
        }
        let currentSeason = season(of: now)
        return games.map { game in
            guard let name = game.tournamentName, !name.isEmpty,
                  let date = game.isoDate ?? game.getDate() else { return game }
            let eventSeason = season(of: date)
            // Idempotent: cached events may already carry the suffix.
            guard eventSeason != currentSeason, !name.hasSuffix(" \(eventSeason)") else { return game }
            var suffixed = game
            suffixed.tournamentName = "\(name) \(eventSeason)"
            return suffixed
        }
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

    /// TheSportsDB publishes a golf tournament as one event *per round* — "The Sentry
    /// Round 1", "… Round 2", "… Final Round" — which puts four rows on the board for one
    /// tournament and matches nothing on the ESPN side, whose event is just "The Sentry".
    /// (The unmatched ESPN row is then appended, so a tournament could show five times.)
    ///
    /// This folds each tournament's rounds back into one event spanning the first round to
    /// the last, which is also where its `endDate` comes from when ESPN hasn't supplied one.
    /// Rows without a round suffix are left exactly as they are.
    static func collapseGolfRounds(_ events: [Game]) -> [Game] {
        func parse(_ name: String) -> (base: String, round: Int)? {
            let lower = name.lowercased()
            if lower.hasSuffix(" final round") {
                // Sorts after any numbered round without assuming how many there were.
                return (String(name.dropLast(" final round".count)), Int.max)
            }
            guard let range = lower.range(of: " round ", options: .backwards) else { return nil }
            let trailing = name[range.upperBound...]
            guard let number = Int(trailing), !trailing.isEmpty else { return nil }
            return (String(name[name.startIndex..<range.lowerBound]), number)
        }

        var groups: [String: [(game: Game, round: Int)]] = [:]
        var output: [Game?] = []
        var slotForGroup: [String: Int] = [:]

        for game in events {
            guard let parsed = parse(game.strHomeTeam), let date = game.isoDate ?? game.getDate() else {
                output.append(game)
                continue
            }
            // Key on the season too: the same tournament comes back every year.
            let year = Calendar(identifier: .gregorian).component(.year, from: date)
            let key = "\(parsed.base.lowercased())|\(year)"
            if slotForGroup[key] == nil {
                slotForGroup[key] = output.count
                output.append(nil)
            }
            groups[key, default: []].append((game, parsed.round))
        }

        for (key, slot) in slotForGroup {
            guard let rounds = groups[key]?.sorted(by: { $0.round < $1.round }),
                  let first = rounds.first?.game, let last = rounds.last?.game else { continue }
            let base = parse(first.strHomeTeam)?.base ?? first.strHomeTeam
            output[slot] = first.updated(
                strHomeTeam: base,
                // The final round's day, so the tournament spans Thursday to Sunday.
                endDate: last.strTimestamp ?? first.strTimestamp
            )
        }

        return output.compactMap { $0 }
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

        // Cheap presence checks only. This runs every minute and skips 59 times an hour;
        // decoding the ~12MB schedule (and the teams list) just to learn "it exists" cost
        // a full JSON parse per tick. The schedule is decoded once, under the write lock,
        // only when a rebuild actually happens.
        let redis = context.application.redis
        let scheduleExists = (try await redis.exists(scheduleKey).get()) > 0
        let teamsPresent = try await Self.hasNonEmptyTeams(redis: redis, key: teamsKey)
        let lastUpdateTime = try await redis.get(lastUpdateKey, asJSON: Date.self)

        // Refresh schedules if missing or if it's been more than 1 hour
        let shouldRefreshSchedules = Self.shouldRefreshSchedules(
            hasSchedule: scheduleExists,
            teamsCount: teamsPresent ? 1 : 0,
            lastUpdate: lastUpdateTime,
            now: Date()
        )
        guard shouldRefreshSchedules else {
            Self.logger.debug("Skipping schedule fetch — using cached data", metadata: [
                "lastUpdate": "\(lastUpdateTime?.description ?? "never")"
            ])
            await JobHeartbeat.recordSuccess(.scheduleUpdate, app: context.application, isDebug: isDebug)
            return
        }
        Self.logger.info("Refreshing schedules from API", metadata: [
            "scheduleExists": "\(scheduleExists)",
            "teamsPresent": "\(teamsPresent)",
            "lastUpdate": "\(lastUpdateTime?.description ?? "never")"
        ])

        Self.logger.info("Fetching schedules from API")
        var schedule: LiveScore = LiveScore(nba: nil, mlb: nil, soccer: nil, nfl: nil, nhl: nil, golf: nil, tennis: nil, racing: nil)
        var apiTeams: [Team] = []
        var allGames: [Game] = []
        // Leagues whose previous games are carried over when this rebuild ends up with
        // none of them (fetch threw, or came back empty). See `applyingLeagueFallbacks`.
        var fallbackLeagues = Set<Leagues>()

        for league in Leagues.allCases {
            // Skip ESPN-only leagues here — handled separately via ESPN below.
            // The secondary golf tours have no TheSportsDB entry at all, and the
            // switch below would drop their response into the soccer bucket.
            if league == .ncaaMBBTournament || league == .wnba || league == .ncaaf { continue }
            if Integrator.secondaryGolfTours.contains(league) { continue }
            // Racing series beyond F1 have their own services (NASCAR, IndyCar, IMSA, WEC), below.
            if league.isMotorsportSeries { continue }
            // Season-scoped fetches (previous/current/next): an empty result means the
            // fetch failed (`getSchedule` swallows per-season errors), never "no games".
            fallbackLeagues.insert(league)
            do {

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
                events.events = SeasonPhase.assignPhases(events.events, league: league)

                // Collect all games for team extraction
                allGames.append(contentsOf: events.events)

                switch league {
                case .nfl:
                    schedule.nfl = events
                    let newGames: [Game] = schedule.nfl?.events.map({ game in
                        if let date = game.getDate(), date.timeIntervalSinceNow > 0 {
                            // Only include essential fields - strSport/strLeague are computed from idLeague
                            // Deprecated fields removed: strPlayer, idPlayer, intEventScore, intEventScoreTotal, strEventTime, dateEvent, updated
                            let newGame = Game(idLiveScore: game.idLiveScore, idEvent: game.idEvent, strSport: nil, idLeague: game.idLeague, strLeague: nil, idHomeTeam: game.idHomeTeam, idAwayTeam: game.idAwayTeam, strHomeTeam: game.strHomeTeam, strAwayTeam: game.strAwayTeam, strHomeTeamBadge: game.strHomeTeamBadge, strAwayTeamBadge: game.strAwayTeamBadge, intHomeScore: nil, intAwayScore: nil, strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: game.strStatus, strProgress: game.strProgress, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: game.strTimestamp, isoDate: game.getDate(), season: game.season, seasonPhase: game.seasonPhase)
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
                    events.events = Self.collapseGolfRounds(events.events)
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
                        var freshTennis: [Game] = []
                        var attempted = 0
                        var succeeded = 0
                        for tour in [Leagues.atp, Leagues.wta] {
                            for year in [currentYear - 1, currentYear] {
                                attempted += 1
                                do {
                                    let scoreboard = try await Integrator.getESPNScoreboard(for: tour, context.application.client, dates: year)
                                    succeeded += 1
                                    if let parsed = LiveEvent(events: scoreboard, league: tour) {
                                        freshTennis.append(contentsOf: parsed.events)
                                    }
                                } catch {
                                    Self.logger.warning("Tennis season fetch failed", metadata: [
                                        "tour": "\(tour)", "year": "\(year)", "error": "\(error)"
                                    ])
                                }
                            }
                        }
                        // A partial failure (one tour/season missing) must not replace the
                        // cache with a partial schedule: merge with the last cached build so
                        // the missing feed's tournaments survive until a full fetch lands.
                        let allSucceeded = succeeded == attempted
                        let cachedTennis = allSucceeded ? nil
                            : (try? await context.application.redis.get(tennisKey, asJSON: LiveEvent.self))?.events
                        let tennisGames = Self.mergeTennisFetch(fresh: freshTennis, cached: cachedTennis, allSucceeded: allSucceeded)
                        if !tennisGames.isEmpty {
                            let built = LiveEvent(events: tennisGames)
                            tennisEvent = built
                            try? await context.application.redis.set(tennisKey, toJSON: built)
                        }
                        // Only a complete fetch is stamped fresh. A partial or failed one is
                        // stamped as already 15 minutes old, so it retries in ~5 minutes
                        // rather than every minute (each attempt is ~12MB per league-year).
                        let stamp = allSucceeded ? Date() : Date().addingTimeInterval(-15 * 60)
                        try? await context.application.redis.set(tennisLastUpdateKey, toJSON: stamp)
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
                        // The sticky cache may predate season disambiguation — apply
                        // it here too (idempotent) so old editions stay suffixed.
                        tennisEvent = LiveEvent(events: Self.disambiguateTennisSeasons(staleCache.events))
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
            // The default board is a today window, so "empty" is legitimate — only a
            // failed fetch keeps the previous games.
            fallbackLeagues.insert(.ncaaMBBTournament)
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
            fallbackLeagues.insert(.wnba)
            Self.logger.warning("WNBA schedule fetch failed: \(error)")
        }

        // College football (ESPN-only). One `dates=<year>` request returns the whole FBS
        // calendar year; from November the next year is fetched too, since the bowls,
        // the CFP and the title game are played in January. Rides in the football bucket
        // — `LiveScore`'s Codable splits it back out on the wire.
        let collegeGames = await Self.fetchCollegeFootballSeason(client: context.application.client)
        // A whole calendar year: empty only when the fetch failed.
        fallbackLeagues.insert(.ncaaf)
        if !collegeGames.isEmpty {
            if schedule.nfl == nil {
                schedule.nfl = LiveEvent(events: collegeGames)
            } else {
                schedule.nfl?.events += collegeGames
            }
            // Not added to `allGames`: that feeds the `/teams` payload, and app versions that
            // predate college football would list ~260 teams they can't show games for.
            // Current clients derive college teams from the games themselves.
            Self.logger.info("College football schedule loaded", metadata: ["events": "\(collegeGames.count)"])
        }

        // Golf tours that exist only on ESPN (TheSportsDB carries the PGA TOUR alone).
        // `usesSingleYearSeason` makes each of these one request for the whole season, and
        // every event carries its own league, so they ride in the same `golf` bucket.
        for tour in Integrator.secondaryGolfTours {
            // Single-year season boards: empty means failed.
            fallbackLeagues.insert(tour)
            do {
                if let scoreboard = try await Integrator.getESPNScoreboard(for: tour, context.application.client) as Scoreboard?,
                   let liveEvent = LiveEvent(events: scoreboard, league: tour) {
                    if schedule.golf == nil {
                        schedule.golf = liveEvent
                    } else {
                        schedule.golf?.events += liveEvent.events
                    }
                    allGames.append(contentsOf: liveEvent.events)
                    Self.logger.info("Golf tour schedule loaded", metadata: [
                        "tour": "\(tour)", "events": "\(liveEvent.events.count)"
                    ])
                }
            } catch {
                Self.logger.warning("Golf tour schedule fetch failed for \(tour): \(error)")
            }
        }

        // NASCAR Cup: NASCAR's own feeds (schedule, every session's results, live state).
        // Appended after the league loop because the F1 case replaces the racing bucket.
        // A failed fetch carries the previous NASCAR games over (`fallbackLeagues`).
        fallbackLeagues.insert(.nascarCup)
        do {
            let nascarGames = try await NASCARService.scheduleGames(app: context.application, isDebug: isDebug)
            schedule.racing = LiveEvent.merging(schedule.racing, LiveEvent(events: nascarGames))
            Self.logger.info("NASCAR schedule loaded", metadata: ["events": "\(nascarGames.count)"])
        } catch {
            Self.logger.warning("NASCAR schedule fetch failed: \(error)")
        }

        // IndyCar: TheSportsDB weekends, ESPN results.
        fallbackLeagues.insert(.indycar)
        do {
            let indyCarGames = try await IndyCarService.scheduleGames(app: context.application, isDebug: isDebug)
            schedule.racing = LiveEvent.merging(schedule.racing, LiveEvent(events: indyCarGames))
            Self.logger.info("IndyCar schedule loaded", metadata: ["events": "\(indyCarGames.count)"])
        } catch {
            Self.logger.warning("IndyCar schedule fetch failed: \(error)")
        }

        // IMSA and WEC: TheSportsDB weekends, Al Kamel's published results.
        for series in AlKamelSeries.allCases {
            fallbackLeagues.insert(series.league)
            do {
                let games = try await AlKamelService.scheduleGames(series, app: context.application, isDebug: isDebug)
                schedule.racing = LiveEvent.merging(schedule.racing, LiveEvent(events: games))
                Self.logger.info("\(series.rawValue) schedule loaded", metadata: ["events": "\(games.count)"])
            } catch {
                Self.logger.warning("\(series.rawValue) schedule fetch failed: \(error)")
            }
        }

        // Enrich schedule with ESPN scoreboard data (records, leaders, linescores, venue, etc.)
        Self.logger.info("Enriching schedule with ESPN scoreboard data")
        schedule = await enrichScheduleWithESPN(schedule: schedule, client: context.application.client)

        // Extract teams from all games (multi-season coverage)
        let gameTeams = extractTeamsFromGames(allGames)
        var mergedTeams = mergeTeams(apiTeams: apiTeams, gameTeams: gameTeams)
        Self.logger.info("Teams extracted and merged", metadata: [
            "fromGames": "\(gameTeams.count)",
            "fromAPI": "\(apiTeams.count)",
            "totalMerged": "\(mergedTeams.count)",
            "totalGames": "\(allGames.count)"
        ])

        // Everything above was network. The rest runs under the shared schedule write
        // lock against the LATEST cached schedule (re-read there), so a concurrent
        // enrichment or ESPN merge that landed during this rebuild is the baseline for
        // the carry-overs below rather than being compared against a stale copy.
        let rebuilt = schedule
        let injuriesKey = RedisEndpoint.ESPN.injuries.getValue(isDebug: isDebug)
        let wcKey = RedisEndpoint.ESPN.worldCupEnrichment.getValue(isDebug: isDebug)
        let cachedInjuries = try? await redis.get(injuriesKey, asJSON: [String: [InjuryReport]].self)
        let cachedWC = try? await redis.get(wcKey, asJSON: WorldCupEnrichment.self)
        var carried: [Leagues: Int] = [:]
        var oldGameCount = 0
        var newGameCount = countGames(in: rebuilt)

        let outcome = try await ScheduleStore.update(
            app: context.application, isDebug: isDebug, logger: Self.logger, writer: "ScheduleUpdateJob"
        ) { existingSchedule in
            oldGameCount = existingSchedule.map { countGames(in: $0) } ?? 0

            // A league whose fetch failed (or came back empty) keeps its previous games
            // instead of vanishing from the calendar for an hour.
            let fallback = Self.applyingLeagueFallbacks(rebuilt: rebuilt, existing: existingSchedule, leagues: fallbackLeagues)
            var schedule = fallback.schedule
            carried = fallback.carried

            // Re-attach cached injuries (InjuriesEnrichmentJob persists the lookup dict
            // but the schedule is rebuilt from scratch here, which would drop per-Game fields)
            if let cachedInjuries, !cachedInjuries.isEmpty {
                InjuriesEnrichmentJob.applyInjuries(to: &schedule, lookup: cachedInjuries)
            }

            // Re-attach the World Cup ridealong from its enrichment cache — the rebuild
            // constructs a fresh LiveScore, and without this every hourly rebuild wiped
            // `worldCup` until WorldCupEnrichmentJob's next :50 run re-attached it
            // (client Bracket CTA flickered out). Mirrors the f1Standings re-attach.
            if schedule.worldCup == nil {
                if let cachedWC, !cachedWC.isEmpty {
                    schedule.worldCup = cachedWC
                } else {
                    schedule.worldCup = existingSchedule?.worldCup
                }
            }

            // Excitement is scored once, when a game goes final, and ESPN drops the game off
            // its board a day later. The rebuild above starts from TheSportsDB, which never
            // has it, so carry it over from the schedule being replaced.
            if let existingSchedule {
                schedule = Self.carryingExcitement(from: existingSchedule, into: schedule)
            }
            newGameCount = countGames(in: schedule)
            return schedule
        }

        if !carried.isEmpty {
            Self.logger.warning("Kept previous schedule for leagues whose fetch failed or came back empty", metadata: [
                "leagues": "\(carried.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ","))"
            ])
            // Their teams would be missing from this run's team list too.
            if let existingTeams = try? await redis.get(teamsKey, asJSON: [Team].self) {
                mergedTeams = mergeTeams(apiTeams: mergedTeams, gameTeams: existingTeams)
            }
        }

        let scheduleChanged: Bool
        switch outcome {
        case .lockTimeout:
            // Nothing written. Leave `lastUpdate` alone so the next minute retries.
            Self.logger.warning("Schedule rebuild not written — schedule write lock busy; retrying next tick")
            return
        case .written:
            scheduleChanged = true
            try await redis.set(RedisEndpoint.SportsDB.teams.getValue(isDebug: isDebug), toJSON: mergedTeams)
            Self.logger.info("Schedules updated — new data detected", metadata: [
                "oldGameCount": "\(oldGameCount)",
                "newGameCount": "\(newGameCount)"
            ])
        case .unchanged:
            scheduleChanged = false
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
        await JobHeartbeat.recordSuccess(.scheduleUpdate, app: context.application, isDebug: isDebug)
    }

    /// Whether the teams key holds a non-empty JSON array, without decoding it.
    /// `[]` is two bytes; anything longer has at least one team.
    static func hasNonEmptyTeams(redis: any RedisClient, key: RedisKey) async throws -> Bool {
        let response = try await redis.send(command: "STRLEN", with: [key.rawValue.convertedToRESPValue()]).get()
        return (response.int ?? 0) > 2
    }

    /// Carries the existing schedule's games for any league in `leagues` that the rebuild
    /// ended up with none of — its fetch threw, or came back empty (TheSportsDB's
    /// `getSchedule` swallows per-season errors and returns nothing). Without this a
    /// single upstream hiccup emptied that league's calendar until the next hourly
    /// rebuild. Games go into the league's sport bucket, skipping any event ID already
    /// there. Also keeps `f1Standings` when the rebuild lost it. Pure, for tests.
    static func applyingLeagueFallbacks(
        rebuilt: LiveScore,
        existing: LiveScore?,
        leagues: Set<Leagues>
    ) -> (schedule: LiveScore, carried: [Leagues: Int]) {
        guard let existing else { return (rebuilt, [:]) }
        var result = rebuilt
        var carried: [Leagues: Int] = [:]
        let rebuiltLeagueIDs = Set(rebuilt.allGamesBySport.flatMap { $0.games.compactMap(\.idLeague) })

        for league in leagues.sorted(by: { $0.rawValue < $1.rawValue }) {
            let leagueID = String(league.rawValue)
            guard !rebuiltLeagueIDs.contains(leagueID) else { continue }
            let sport = SportType(league: league)
            guard let keyPath = LiveScore.sportKeyPaths.first(where: { $0.0 == sport })?.1 else { continue }
            let previous = existing[keyPath: keyPath]?.events.filter { $0.idLeague == leagueID } ?? []
            guard !previous.isEmpty else { continue }
            let present = Set(result[keyPath: keyPath]?.events.compactMap(\.idEvent) ?? [])
            let toAdd = previous.filter { game in
                guard let id = game.idEvent else { return true }
                return !present.contains(id)
            }
            guard !toAdd.isEmpty else { continue }
            result[keyPath: keyPath] = LiveEvent.merging(result[keyPath: keyPath], LiveEvent(events: toAdd))
            carried[league] = toAdd.count
        }
        if result.f1Standings == nil, let standings = existing.f1Standings {
            result.f1Standings = standings
        }
        return (result, carried)
    }

    /// Combines this run's tennis fetches with the previously cached build. When every
    /// fetch succeeded the fresh games are the whole truth; otherwise cached games the
    /// fresh set lacks are kept, so a failed tour/season doesn't drop its tournaments.
    /// Deduped by event ID (combined events like the United Cup appear on both the ATP
    /// and WTA boards) and season-disambiguated. Pure, for tests.
    static func mergeTennisFetch(fresh: [Game], cached: [Game]?, allSucceeded: Bool, now: Date = Date()) -> [Game] {
        var seen = Set<String>()
        var games = fresh.filter { game in
            guard let id = game.idEvent else { return true }
            return seen.insert(id).inserted
        }
        if !allSucceeded, let cached {
            games += cached.filter { game in
                guard let id = game.idEvent else { return false }
                return seen.insert(id).inserted
            }
        }
        return disambiguateTennisSeasons(games, now: now)
    }
    /// Every FBS game of the current calendar year, plus next January's from November on,
    /// deduped by event ID (a game can sit on both years' boards across midnight UTC).
    static func fetchCollegeFootballSeason(client: any Client, now: Date = Date()) async -> [Game] {
        var games: [Game] = []
        var seen = Set<String>()
        for year in collegeFootballScheduleYears(now: now) {
            do {
                let scoreboard = try await Integrator.getESPNScoreboard(for: .ncaaf, client, dates: year)
                for game in LiveEvent(events: scoreboard, league: .ncaaf)?.events ?? [] {
                    if let id = game.idEvent, !seen.insert(id).inserted { continue }
                    games.append(game)
                }
            } catch {
                logger.warning("College football schedule fetch failed", metadata: ["year": "\(year)", "error": "\(error)"])
            }
        }
        return games
    }

    /// The calendar years whose ESPN boards make up the college football schedule.
    static func collegeFootballScheduleYears(now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> [Int] {
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        // January–February: last season's regular season lives in last year's board, and
        // the schedule is rebuilt from scratch — without it, team pages would show only
        // the bowl game until August.
        if month <= 2 { return [year - 1, year] }
        return month >= 11 ? [year, year + 1] : [year]
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

    /// Merges ESPN enrichment fields into TheSportsDB schedule games by matching team
    /// names + day, disambiguated by nearest kickoff (same teams can meet twice on one
    /// UTC day — see `ESPNFetchJob.closestByKickoff`). Single-value day keys here
    /// overlaid one game's ESPN status/fields onto the matchup's other game.
    /// Copies `excitement` from `old` onto games in `new` that lack it, by event ID.
    static func carryingExcitement(from old: LiveScore, into new: LiveScore) -> LiveScore {
        var scores: [String: Int] = [:]
        for (_, games) in old.allGamesBySport {
            for game in games {
                if let id = game.idEvent, let excitement = game.excitement { scores[id] = excitement }
            }
        }
        guard !scores.isEmpty else { return new }
        return ESPNFetchJob.applyingExcitement(scores, to: new)
    }

    func mergeEnrichment(schedule: LiveEvent, espn: LiveEvent) -> LiveEvent {
        // Build ESPN lookup by team names + day
        var espnByNames: [String: [Game]] = [:]
        var espnByNormalized: [String: [Game]] = [:]
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
            espnByNames[key, default: []].append(game)

            let normalizedKey = "\(normalizeTeamName(game.strHomeTeam))|\(normalizeTeamName(game.strAwayTeam))|\(day)"
            espnByNormalized[normalizedKey, default: []].append(game)

            // Also index by team ID for better matching
            if let homeID = game.idHomeTeam, let awayID = game.idAwayTeam {
                let idKey = "\(homeID)|\(awayID)|\(day)"
                espnByNames[idKey, default: []].append(game)
            }
        }

        let merged = schedule.events.map { scheduleGame -> Game in
            // College games come straight from ESPN already, and share the football bucket
            // with an NFL board whose untranslated ESPN team IDs overlap college ones.
            if scheduleGame.isCollegeFootball { return scheduleGame }
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
            var espnMatch = ESPNFetchJob.closestByKickoff(espnByNames[nameKey], to: scheduleGame)

            // Try matching by team IDs
            if espnMatch == nil, let homeID = scheduleGame.idHomeTeam, let awayID = scheduleGame.idAwayTeam {
                let idKey = "\(homeID)|\(awayID)|\(day)"
                espnMatch = ESPNFetchJob.closestByKickoff(espnByNames[idKey], to: scheduleGame)
            }

            // Fallback: normalized team names (handles "LA" vs "Los Angeles" etc.)
            if espnMatch == nil {
                let normalizedKey = "\(normalizeTeamName(scheduleGame.strHomeTeam))|\(normalizeTeamName(scheduleGame.strAwayTeam))|\(day)"
                espnMatch = ESPNFetchJob.closestByKickoff(espnByNormalized[normalizedKey], to: scheduleGame)
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
                homeConference: espnGame.homeConference ?? scheduleGame.homeConference,
                awayConference: espnGame.awayConference ?? scheduleGame.awayConference,
                playoff: espnGame.playoff ?? scheduleGame.playoff,
                season: scheduleGame.season ?? espnGame.season,
                // ESPN's season.type is authoritative; TheSportsDB's round codes are the fallback.
                seasonPhase: espnGame.seasonPhase ?? scheduleGame.seasonPhase,
                situation: espnGame.situation,
                excitement: espnGame.excitement ?? scheduleGame.excitement
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
