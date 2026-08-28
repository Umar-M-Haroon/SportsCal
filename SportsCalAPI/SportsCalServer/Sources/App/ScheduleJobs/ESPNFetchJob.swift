//
//  File.swift
//  
//
//  Created by Umar Haroon on 2/23/23.
//

import Foundation
import Vapor
import Queues
import RediStack
import SportsCalModel
import Logging
import VaporAPNS
import APNSCore

struct ESPNFetchJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.espn-fetch")
    
    func run(context: Queues.QueueContext) async throws {
        let isDebug = context.application.environment == .development

        // Leader-election: only one replica may execute a given tick.
        //
        // ttl was 50s, sized against the next minutely tick back when this job made ~28
        // upstream requests. The hourly forward-window refresh now makes ~480, which can
        // outlast 50s on a slow ESPN — the lock would then expire mid-run and the next tick
        // would execute runUnderLock concurrently: racing `latestSchedule` writes and, worse,
        // duplicate push-to-start notifications (sendPushToStartForNewGames diffs against a
        // `latestLiveInfo` the other run is rewriting). 180s covers the heavy tick; the cost
        // of a crashed run is skipping at most two minutely ticks, which is harmless.
        _ = try await JobLock.withLock(
            context.application.kv,
            name: "espn-fetch",
            ttl: 180,
            instanceID: context.application.instanceID,
            logger: Self.logger,
            body: { try await self.runUnderLock(context: context, isDebug: isDebug) }
        )
    }

    private func runUnderLock(context: Queues.QueueContext, isDebug: Bool) async throws {
        // Prune any cached "in-progress" games whose scheduled start is >8h in the past.
        // Runs every tick — including ticks where we skip the ESPN fetch — so a game that
        // ended during an idle window doesn't stay pinned as live forever.
        await pruneStaleCachedLiveGames(context: context, isDebug: isDebug)

        // Compute the active-league set once. nil = cold start (both schedule sources
        // empty) — treat as "fetch everything" so we populate cache for the next tick.
        let active = await Integrator.activeLeagues(redis: context.application.redis, isDebug: isDebug)
        if let active, active.isEmpty {
            // Nothing is live, so skip the live-score work — but still refresh the forward
            // schedule window. It is the schedule backfill, and a quiet period is exactly
            // when the calendar is emptiest and it matters most; returning here would leave
            // it dead through every offseason. It is internally gated to once an hour.
            Self.logger.info("No live or upcoming games — skipping ESPN live score fetch")
            await refreshForwardWindowIntoSchedule(context: context, isDebug: isDebug, liveResult: nil)
            return
        }

        let soccerScoreboards = try await context.application.redis.get( RedisEndpoint.ESPN.latestSoccerScoreboards.getValue(isDebug: isDebug), asJSON: [Leagues: Scoreboard].self)

        let soccerEvents = soccerScoreboards?.compactMap({ (league, scoreboard) in
            LiveEvent(events: scoreboard, league: league)
        }).reduce(into: LiveEvent(events: [])) { partialResult, next in
            partialResult.events += next.events
        }

        let tennisScoreboards = try await context.application.redis.get( RedisEndpoint.ESPN.latestTennisScoreboards.getValue(isDebug: isDebug), asJSON: [Leagues: Scoreboard].self)

        let tennisEvents = tennisScoreboards?.compactMap({ (league, scoreboard) in
            LiveEvent(events: scoreboard, league: league)
        }).reduce(into: LiveEvent(events: [])) { partialResult, next in
            partialResult.events += next.events
        }

        Self.logger.info("Fetching ESPN live scores", metadata: [
            "activeLeagues": "\(active?.count ?? -1)"  // -1 = cold start, fetch-all
        ])
        let espnResult = await Integrator.getESPNLiveScore(context.application.client, activeLeagues: active)

        let latestLiveResult = try await context.application.redis.get(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug), asJSON: LiveScore.self)

        // Load ESPN-ID → TheSportsDB-ID mapping for team ID translation
        let mappingKey: RedisKey = isDebug ? "debug-ESPN-ID-Map" : "ESPN-ID-Map"
        let espnToTSDB = try await context.application.redis.get(mappingKey, asJSON: [String: String].self) ?? [:]

        // Build alias resolver from the cached teams payload (populated by ESPNTeamFetchJob).
        // Used by mergeSportEvents to collapse duplicates whose team names differ across
        // ESPN/TSDB but resolve to the same TSDB team via strAlternate or curated aliases.
        let cachedTeams = try await context.application.redis.get(
            RedisEndpoint.teams.getValue(isDebug: isDebug),
            asJSON: [Team].self
        ) ?? []
        let aliasResolver = TeamAliasResolver(teams: cachedTeams, logger: Self.logger)

        var newResult = latestLiveResult.map({ score in
            return LiveScore(nba: returnUpdatedEvents(events: [], espnEvents: espnResult.nba?.events ?? []),
                             mlb: returnUpdatedEvents(events:  [], espnEvents: espnResult.mlb?.events ?? []),
                             soccer: returnUpdatedEvents(events: [], espnEvents: soccerEvents?.events ?? []),
                             nfl: returnUpdatedEvents(events: [], espnEvents: espnResult.nfl?.events ?? []),
                             nhl: returnUpdatedEvents(events: [], espnEvents: espnResult.nhl?.events ?? []),
                             golf: returnUpdatedEvents(events: [], espnEvents: espnResult.golf?.events ?? []),
                             tennis: returnUpdatedEvents(events: [], espnEvents: tennisEvents?.events ?? []),
                             racing: returnUpdatedEvents(events: [], espnEvents: espnResult.racing?.events ?? []))
        })
        if newResult == nil {
            newResult = espnResult
        }

        // Per-event play-by-play enrichment runs against `newResult` (which has soccer/tennis
        // merged in) BEFORE team ID translation strips `lastPlayScoreboardID` off rebuilt games.
        // Side-effect only: writes to SQLite / Redis under PBP-{id}.
        if let current = newResult {
            await enrichWithPlays(from: current, context: context, isDebug: isDebug)
        }

        // Translate ESPN team IDs to TheSportsDB IDs in all live games
        // This must happen BEFORE merging NCAA games, since ESPN IDs are per-sport
        // and NCAA team IDs can collide with NBA team IDs in the mapping
        if !espnToTSDB.isEmpty {
            newResult = newResult.map { translateTeamIDs(in: $0, using: espnToTSDB) }
        }

        // Merge NCAA Tournament into basketball AFTER ID translation to avoid
        // NCAA ESPN IDs being incorrectly mapped to NBA TheSportsDB IDs
        let shouldFetchNCAA = active?.contains(.ncaaMBBTournament) ?? true
        if shouldFetchNCAA,
           let ncaaScoreboard = try? await Integrator.getESPNScoreboard(for: .ncaaMBBTournament, context.application.client),
           let ncaaLiveEvent = LiveEvent(events: ncaaScoreboard, league: .ncaaMBBTournament) {
            if let existing = newResult?.nba {
                newResult = newResult.map { result in
                    LiveScore(nba: LiveEvent(events: existing.events + ncaaLiveEvent.events), mlb: result.mlb, soccer: result.soccer, nfl: result.nfl, nhl: result.nhl, golf: result.golf, tennis: result.tennis, racing: result.racing)
                }
            } else {
                newResult = newResult.map { result in
                    LiveScore(nba: ncaaLiveEvent, mlb: result.mlb, soccer: result.soccer, nfl: result.nfl, nhl: result.nhl, golf: result.golf, tennis: result.tennis, racing: result.racing)
                }
                if newResult == nil {
                    newResult = LiveScore(nba: ncaaLiveEvent)
                }
            }
        }

        // Same pattern for WNBA — ESPN-only league sharing the basketball bucket
        let shouldFetchWNBA = active?.contains(.wnba) ?? true
        if shouldFetchWNBA,
           let wnbaScoreboard = try? await Integrator.getESPNScoreboard(for: .wnba, context.application.client),
           let wnbaLiveEvent = LiveEvent(events: wnbaScoreboard, league: .wnba) {
            if let existing = newResult?.nba {
                newResult = newResult.map { result in
                    LiveScore(nba: LiveEvent(events: existing.events + wnbaLiveEvent.events), mlb: result.mlb, soccer: result.soccer, nfl: result.nfl, nhl: result.nhl, golf: result.golf, tennis: result.tennis, racing: result.racing)
                }
            } else {
                newResult = newResult.map { result in
                    LiveScore(nba: wnbaLiveEvent, mlb: result.mlb, soccer: result.soccer, nfl: result.nfl, nhl: result.nhl, golf: result.golf, tennis: result.tennis, racing: result.racing)
                }
                if newResult == nil {
                    newResult = LiveScore(nba: wnbaLiveEvent)
                }
            }
        }

        // Detect newly started games and send push-to-start notifications
        if let newResult {
            await sendPushToStartForNewGames(
                newResult: newResult,
                previousResult: latestLiveResult,
                context: context,
                isDebug: isDebug
            )
        }

        try await context.application.redis.setex(RedisEndpoint.ESPN.latestFullLiveInfo.getValue(isDebug: isDebug), toJSON: newResult, expirationInSeconds: 60 * 30)
        try await context.application.redis.set(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug), toJSON: newResult)

        // Merge ESPN data into cached schedule so /schedules reflects live scores, and pull
        // forward the upcoming-days window so the calendar is populated months ahead.
        await refreshForwardWindowIntoSchedule(
            context: context, isDebug: isDebug, liveResult: newResult, resolver: aliasResolver
        )
    }

    /// Merges the forward schedule window — and the live result when there is one — into the
    /// cached schedule. Split out of `runUnderLock` so the quiet-period path can still run the
    /// backfill without doing the live-score work.
    private func refreshForwardWindowIntoSchedule(
        context: Queues.QueueContext,
        isDebug: Bool,
        liveResult: LiveScore?,
        resolver: TeamAliasResolver? = nil
    ) async {
        let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
        guard let schedule = try? await context.application.redis.get(scheduleKey, asJSON: LiveScore.self) else { return }

        // ~4 months: far enough that the calendar and browse are populated for the
        // whole upcoming NBA/NHL season even while TheSportsDB is still catching up.
        var window = await fetchForwardScheduleWindowIfStale(context: context, isDebug: isDebug, daysAhead: 120)

        // The window is raw ESPN, so it carries ESPN team ids. The rest of the schedule is
        // keyed by TheSportsDB ids (the live result was translated before it got here), and
        // anything appended from the window is what the client sees for months of upcoming
        // fixtures — untranslated, team-id lookups like TeamDetailView silently miss them.
        let mappingKey: RedisKey = isDebug ? "debug-ESPN-ID-Map" : "ESPN-ID-Map"
        if let espnToTSDB = try? await context.application.redis.get(mappingKey, asJSON: [String: String].self),
           !espnToTSDB.isEmpty {
            window = translateTeamIDs(in: window, using: espnToTSDB)
        }

        // Dedup across the two sources before merging: `merging` is a plain concatenation,
        // and the same fixture can be in both the live board and the window's first day
        // (ESPN's day boundaries are timezone-shifted). Without this, a game TheSportsDB
        // doesn't have yet — exactly the backfill case — gets appended twice.
        let enriched = Self.dedupedByEventID(liveResult?.merging(with: window) ?? window)

        // Reuse the caller's resolver when there is one; otherwise load the cached teams so
        // the quiet path gets the same alias-collapsing the live path does.
        var aliasResolver = resolver
        if aliasResolver == nil {
            let teams = (try? await context.application.redis.get(
                RedisEndpoint.teams.getValue(isDebug: isDebug), asJSON: [Team].self
            )) ?? []
            aliasResolver = TeamAliasResolver(teams: teams, logger: Self.logger)
        }
        let updated = mergeESPNIntoSchedule(schedule: schedule, espn: enriched, resolver: aliasResolver!)
        if updated != schedule {
            try? await context.application.redis.set(scheduleKey, toJSON: updated)
            Self.logger.info("Schedule updated with ESPN live data")
        }
    }

    // MARK: - Stale Cache Prune

    private func pruneStaleCachedLiveGames(context: Queues.QueueContext, isDebug: Bool) async {
        let liveKey = RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug)
        let fullKey = RedisEndpoint.ESPN.latestFullLiveInfo.getValue(isDebug: isDebug)

        guard var cached = try? await context.application.redis.get(liveKey, asJSON: LiveScore.self) else { return }
        let removed = cached.removeStaleLiveGames()
        guard removed > 0 else { return }

        Self.logger.info("Pruned \(removed) stale in-progress game(s) from live cache")
        try? await context.application.redis.set(liveKey, toJSON: cached)
        // Mirror to the detailed (30-min TTL) key if it still exists, so consumers of
        // /all-live-games see the prune too.
        if let exists = try? await context.application.redis.exists(fullKey), exists > 0 {
            try? await context.application.redis.set(fullKey, toJSON: cached)
        }
    }

    // MARK: - Play-by-Play Enrichment (NBA / NFL / NHL / MLB)

    private struct PBPCandidate {
        let game: Game
        let sport: String      // "basketball" | "baseball" | "football" | "hockey"
        let league: String     // "nba" | "mlb" | "nfl" | "nhl"
        /// TheSportsDB event ID for the same game, resolved via schedule matching.
        /// When present, plays are cached under this key so iOS clients (which carry
        /// TSDB IDs after the schedule merge) hit the cache on /plays/:eventID.
        let tsdbEventID: String?
    }

    /// Enriches live NBA/NFL/NHL/MLB games with full play-by-play data from ESPN's
    /// `/summary?event={id}` endpoint, writing per-event `CachedPlays` to Redis.
    ///
    /// Conditional on `lastPlay.id` from the scoreboard — if the cached ID already matches,
    /// we skip the ESPN call entirely. Bounded at 6 concurrent fetches to keep ESPN load low.
    private func enrichWithPlays(
        from liveScore: LiveScore,
        context: Queues.QueueContext,
        isDebug: Bool
    ) async {
        // The iOS client carries TheSportsDB event IDs after the schedule merge, while
        // espnResult carries ESPN IDs. Load the schedule to bridge them.
        let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
        let schedule: LiveScore? = try? await context.application.redis.get(scheduleKey, asJSON: LiveScore.self)

        var candidates: [PBPCandidate] = []
        for game in liveScore.nba?.events ?? [] where shouldEnrichPBP(game) {
            candidates.append(PBPCandidate(
                game: game, sport: "basketball", league: "nba",
                tsdbEventID: findTSDBEventID(for: game, in: schedule?.nba?.events)
            ))
        }
        for game in liveScore.nfl?.events ?? [] where shouldEnrichPBP(game) {
            candidates.append(PBPCandidate(
                game: game, sport: "football", league: "nfl",
                tsdbEventID: findTSDBEventID(for: game, in: schedule?.nfl?.events)
            ))
        }
        for game in liveScore.nhl?.events ?? [] where shouldEnrichPBP(game) {
            candidates.append(PBPCandidate(
                game: game, sport: "hockey", league: "nhl",
                tsdbEventID: findTSDBEventID(for: game, in: schedule?.nhl?.events)
            ))
        }
        for game in liveScore.mlb?.events ?? [] where shouldEnrichPBP(game) {
            candidates.append(PBPCandidate(
                game: game, sport: "baseball", league: "mlb",
                tsdbEventID: findTSDBEventID(for: game, in: schedule?.mlb?.events)
            ))
        }
        // Soccer spans many leagues — each game's ESPN slug comes from its `idLeague`
        // (EPL → eng.1, La Liga → esp.1, etc. — see Leagues.espnSlug).
        for game in liveScore.soccer?.events ?? [] where shouldEnrichPBP(game) {
            guard let leagueID = game.idLeague, let leagueInt = Int(leagueID),
                  let leagueEnum = Leagues(rawValue: leagueInt),
                  let slug = leagueEnum.espnSlug else { continue }
            candidates.append(PBPCandidate(
                game: game, sport: "soccer", league: slug,
                tsdbEventID: findTSDBEventID(for: game, in: schedule?.soccer?.events)
            ))
        }

        guard !candidates.isEmpty else { return }

        // Merge new [tsdbID → espnID/sport/league] into the persistent ESPN-Event-Map so the
        // /plays/:eventID on-demand path can resolve a client-supplied TSDB ID back to ESPN.
        await updateEventIDMap(candidates: candidates, context: context, isDebug: isDebug)

        var fetched = 0
        var skipped = 0
        var failed = 0

        await withTaskGroup(of: PBPResult.self) { group in
            let maxConcurrent = 6
            var iterator = candidates.makeIterator()
            var inFlight = 0

            func addNext() {
                guard let candidate = iterator.next() else { return }
                inFlight += 1
                group.addTask { [self] in
                    await processPBPCandidate(candidate, context: context, isDebug: isDebug)
                }
            }

            for _ in 0..<min(maxConcurrent, candidates.count) { addNext() }

            while let result = await group.next() {
                inFlight -= 1
                switch result {
                case .fetched: fetched += 1
                case .skipped: skipped += 1
                case .failed:  failed  += 1
                }
                addNext()
            }
        }

        Self.logger.info("PBP enrichment: fetched \(fetched), skipped \(skipped) (unchanged lastPlay.id), failed \(failed)")
    }

    /// Whether a game should be considered for PBP enrichment.
    /// Live in-progress games always qualify. Completed games qualify once (to capture the
    /// full final PBP) — callers must additionally check the Redis cache to avoid re-fetching.
    private func shouldEnrichPBP(_ game: Game) -> Bool {
        guard game.idEvent != nil else { return false }
        if game.strStatus == "in" { return true }
        if game.strStatus == "post" && game.isCompleted == true { return true }
        return false
    }

    private enum PBPResult {
        case fetched
        case skipped
        case failed
    }

    /// Matches an ESPN game to a scheduled (TSDB) game by team names + day.
    /// Returns the schedule game's `idEvent` (TSDB ID) when a match is found.
    private func findTSDBEventID(for espnGame: Game, in scheduleEvents: [Game]?) -> String? {
        guard let scheduleEvents, !scheduleEvents.isEmpty else { return nil }
        let espnDay = dayString(from: espnGame)
        let espnHome = normalizeTeamName(espnGame.strHomeTeam)
        let espnAway = normalizeTeamName(espnGame.strAwayTeam)
        for scheduleGame in scheduleEvents {
            let scheduleDay = dayString(from: scheduleGame)
            guard espnDay == scheduleDay else { continue }
            let scheduleHome = normalizeTeamName(scheduleGame.strHomeTeam)
            let scheduleAway = normalizeTeamName(scheduleGame.strAwayTeam)
            if scheduleHome == espnHome && scheduleAway == espnAway {
                return scheduleGame.idEvent
            }
        }
        return nil
    }

    /// Merges a per-candidate [tsdbID → EventIDMapping] dictionary into the persistent
    /// `ESPN-Event-Map` Redis key so the /plays/:eventID route can do on-demand lookups.
    private func updateEventIDMap(
        candidates: [PBPCandidate],
        context: Queues.QueueContext,
        isDebug: Bool
    ) async {
        var additions: [String: ESPNEventMapping] = [:]
        for candidate in candidates {
            guard let tsdbID = candidate.tsdbEventID,
                  let espnID = candidate.game.idEvent else { continue }
            additions[tsdbID] = ESPNEventMapping(
                espnEventID: espnID, sport: candidate.sport, league: candidate.league
            )
        }
        guard !additions.isEmpty else { return }
        let mapKey = RedisEndpoint.ESPN.espnEventMap.getValue(isDebug: isDebug)
        var existing: [String: ESPNEventMapping] = (try? await context.application.redis.get(
            mapKey, asJSON: [String: ESPNEventMapping].self
        )) ?? [:]
        for (k, v) in additions { existing[k] = v }
        try? await context.application.redis.set(mapKey, toJSON: existing)
    }

    private func processPBPCandidate(
        _ candidate: PBPCandidate,
        context: Queues.QueueContext,
        isDebug: Bool
    ) async -> PBPResult {
        guard let espnEventID = candidate.game.idEvent else { return .failed }
        // Prefer the TSDB key (what iOS clients send). Fall back to ESPN ID if no match.
        let primaryKey: RedisKey
        let secondaryKey: RedisKey?
        if let tsdbID = candidate.tsdbEventID {
            primaryKey = RedisEndpoint.ESPN.playByPlay(tsdbID).getValue(isDebug: isDebug)
            secondaryKey = RedisEndpoint.ESPN.playByPlay(espnEventID).getValue(isDebug: isDebug)
        } else {
            primaryKey = RedisEndpoint.ESPN.playByPlay(espnEventID).getValue(isDebug: isDebug)
            secondaryKey = nil
        }

        let cached = try? await context.application.redis.get(primaryKey, asJSON: CachedPlays.self)

        let isFinal = (candidate.game.strStatus == "post" && candidate.game.isCompleted == true)

        // Skip path: the cached snapshot matches the current scoreboard lastPlay.id
        // AND its finality state matches. This is the common case during live play when
        // nothing has changed between :15 ticks.
        if let cached,
           let currentLastPlayID = candidate.game.lastPlayScoreboardID,
           cached.lastPlayId == currentLastPlayID,
           cached.isFinal == isFinal {
            return .skipped
        }

        do {
            let summary = try await ESPNNetworking.getPlayByPlaySummary(
                req: context.application.client,
                sport: candidate.sport,
                league: candidate.league,
                eventId: espnEventID
            )
            let plays = summary.plays ?? []
            let clientFacingID = candidate.tsdbEventID ?? espnEventID
            let payload = CachedPlays(
                eventID: clientFacingID,
                lastPlayId: plays.last?.id ?? candidate.game.lastPlayScoreboardID ?? "",
                plays: plays,
                isFinal: isFinal,
                fetchedAt: Date()
            )
            if isFinal {
                // Final state: persist to the SQLite archive (durable, no TTL) and flush the
                // hot Redis keys so we don't double-store the same blob. Falls back to a Redis
                // 24h TTL if the archive isn't available for some reason.
                if let archive = context.application.pbpArchive {
                    do {
                        try await archive.upsert(
                            cached: payload,
                            espnEventID: espnEventID,
                            tsdbEventID: candidate.tsdbEventID,
                            sport: candidate.sport,
                            league: candidate.league
                        )
                        _ = try? await context.application.redis.delete(primaryKey).get()
                        if let secondaryKey {
                            _ = try? await context.application.redis.delete(secondaryKey).get()
                        }
                    } catch {
                        Self.logger.warning("PBP archive upsert failed — falling back to Redis TTL", metadata: [
                            "eventID": "\(espnEventID)", "error": "\(error)"
                        ])
                        try await context.application.redis.setex(
                            primaryKey, toJSON: payload, expirationInSeconds: 60 * 60 * 24
                        )
                    }
                } else {
                    try await context.application.redis.setex(
                        primaryKey, toJSON: payload, expirationInSeconds: 60 * 60 * 24
                    )
                    if let secondaryKey {
                        try? await context.application.redis.setex(
                            secondaryKey, toJSON: payload, expirationInSeconds: 60 * 60 * 24
                        )
                    }
                }
            } else {
                // Live: no TTL, overwritten next tick when `lastPlay.id` changes.
                try await context.application.redis.set(primaryKey, toJSON: payload)
                if let secondaryKey {
                    try? await context.application.redis.set(secondaryKey, toJSON: payload)
                }
            }
            return .fetched
        } catch {
            Self.logger.debug("PBP fetch failed", metadata: [
                "sport": "\(candidate.sport)",
                "eventID": "\(espnEventID)",
                "error": "\(error)"
            ])
            return .failed
        }
    }

    // MARK: - Forward schedule window

    /// Max ESPN day-board fetches in flight while building the forward window.
    static let forwardWindowConcurrency = 6

    /// Collapses duplicate events within each sport bucket, keeping first occurrence.
    /// `LiveScore.merging` concatenates without dedup, so the live board and the forward
    /// window can each contribute the same fixture. `internal` for tests.
    static func dedupedByEventID(_ score: LiveScore) -> LiveScore {
        func dedup(_ event: LiveEvent?) -> LiveEvent? {
            guard let event else { return nil }
            var seen = Set<String>()
            return LiveEvent(events: event.events.filter { game in
                guard let id = game.idEvent else { return true }
                return seen.insert(id).inserted
            })
        }
        return LiveScore(
            nba: dedup(score.nba), mlb: dedup(score.mlb), soccer: dedup(score.soccer),
            nfl: dedup(score.nfl), nhl: dedup(score.nhl), golf: dedup(score.golf),
            tennis: dedup(score.tennis), racing: dedup(score.racing),
            f1Standings: score.f1Standings, worldCup: score.worldCup
        )
    }

    /// Fetches one league's next `daysAhead` day-boards and returns its games, deduped by
    /// event id. Bounded at `forwardWindowConcurrency` in flight — an unbounded fan-out here
    /// would fire `daysAhead` requests at ESPN at once and trip its global 429 breaker, which
    /// halts *all* ESPN traffic.
    ///
    /// Days are keyed in US Eastern because that is how ESPN buckets its boards; the id dedup
    /// absorbs the resulting overlap at the UTC boundary. `internal` so tests can drive the
    /// real implementation rather than a copy of it.
    static func forwardWindowGames(
        league: Leagues,
        daysAhead: Int,
        client: some Client,
        now: Date = Date()
    ) async -> [Game] {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        df.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = df.timeZone

        let days: [Int] = (1...max(1, daysAhead)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
            return Int(df.string(from: date))
        }

        var collected: [Game] = []
        var iterator = days.makeIterator()
        await withTaskGroup(of: [Game].self) { group in
            func addNext() {
                guard let ymd = iterator.next() else { return }
                group.addTask {
                    do {
                        let scoreboard = try await Integrator.getESPNScoreboard(for: league, client, dates: ymd)
                        return LiveEvent(events: scoreboard, league: league)?.events ?? []
                    } catch {
                        logger.debug("Forward window fetch failed", metadata: [
                            "league": "\(league)", "date": "\(ymd)", "error": "\(error)"
                        ])
                        return []
                    }
                }
            }
            for _ in 0..<min(forwardWindowConcurrency, days.count) { addNext() }
            while let games = await group.next() {
                collected.append(contentsOf: games)
                addNext()
            }
        }

        var seen = Set<String>()
        return collected.filter { game in
            guard let id = game.idEvent else { return true }
            return seen.insert(id).inserted
        }
    }

    /// Fetches ESPN scoreboards for the next `daysAhead` days for each of the four big
    /// team leagues and caches the result.
    ///
    /// This is also our schedule backfill. TheSportsDB is the primary schedule source, but
    /// it publishes new seasons late — in Aug 2026 it carried 17 NBA games for all of
    /// 2026-27 while ESPN had the full season — so a TSDB-only schedule leaves the calendar
    /// empty months ahead. Everything ESPN reports in the window is carried (not just
    /// `playoff != nil`, which was the old behaviour and dropped every regular-season game);
    /// `mergeESPNIntoSchedule` then matches what TSDB already has and appends only the rest.
    ///
    /// Safe to re-run: the hourly TheSportsDB rebuild resets the schedule from scratch, and
    /// the append path's `alreadyScheduled` check drops any fixture TSDB has since published,
    /// so appended games can't accumulate or duplicate.
    ///
    /// Refreshed every 60 minutes — the fetch is bounded at
    /// `forwardWindowConcurrency` in flight, so the wider horizon costs seconds, not minutes.
    private func fetchForwardScheduleWindowIfStale(
        context: Queues.QueueContext,
        isDebug: Bool,
        daysAhead: Int
    ) async -> LiveScore {
        let cacheKey = RedisEndpoint.ESPN.postseasonWindow.getValue(isDebug: isDebug)
        let updateKey = RedisEndpoint.ESPN.postseasonWindowLastUpdate.getValue(isDebug: isDebug)

        // The claim alone paces refreshes — deliberately NOT `claim && cachedExists`.
        // Requiring the cached value too means a missing/evicted `cacheKey` (first boot,
        // maxmemory eviction, or the `try?`-swallowed setex failing on a multi-MB value)
        // makes this fall through on EVERY minutely tick and start another 480-request
        // window. Returning an empty window for the rest of the hour is the safe failure:
        // the schedule keeps whatever it already had, and the next hour retries.
        if let lastUpdate = try? await context.application.redis.get(updateKey, asJSON: Date.self),
           Date().timeIntervalSince(lastUpdate) < 60 * 60 {
            return (try? await context.application.redis.get(cacheKey, asJSON: LiveScore.self)) ?? LiveScore()
        }

        // Claim the refresh BEFORE fetching, not after. This job's JobLock ttl (50s) was
        // sized when the window was 28 sequential requests; it is now 480, which can
        // outlast the lock. If the marker were only written on completion, every
        // subsequent minutely tick would see a stale marker, take the expired lock, and
        // start its own 480-request window — runs stacking until ESPN's global 429
        // breaker trips and halts all ESPN traffic. Claiming up front bounds this to one
        // refresh per hour no matter how long a run takes or how it fails.
        //
        // The claim carries a TTL slightly over the refresh interval so a process that
        // dies mid-refresh cannot wedge the window permanently; the previous window stays
        // served from `cacheKey` in the meantime.
        try? await context.application.redis.setex(updateKey, toJSON: Date(), expirationInSeconds: 60 * 70)

        let playoffLeagues: [(league: Leagues, sport: SportType)] = [
            (.nba, .basketball), (.nhl, .hockey), (.mlb, .mlb), (.nfl, .nfl)
        ]

        var eventsBySport: [SportType: [Game]] = [:]
        for (league, sport) in playoffLeagues {
            let collected = await Self.forwardWindowGames(
                league: league, daysAhead: daysAhead, client: context.application.client
            )
            if !collected.isEmpty {
                eventsBySport[sport] = collected
            }
        }

        let window = LiveScore(
            nba: eventsBySport[.basketball].map { LiveEvent(events: $0) },
            mlb: eventsBySport[.mlb].map { LiveEvent(events: $0) },
            nfl: eventsBySport[.nfl].map { LiveEvent(events: $0) },
            nhl: eventsBySport[.hockey].map { LiveEvent(events: $0) }
        )

        // Cache TTL is deliberately longer than the refresh interval: the marker above is
        // what paces refreshes, and keeping the last good window past its refresh window
        // means a failed refresh degrades to slightly-stale rather than to nothing.
        try? await context.application.redis.setex(cacheKey, toJSON: window, expirationInSeconds: 60 * 90)
        let total = [window.nba, window.mlb, window.nfl, window.nhl].compactMap { $0?.events.count }.reduce(0, +)
        Self.logger.info("Forward schedule window refreshed", metadata: [
            "daysAhead": "\(daysAhead)", "totalGames": "\(total)"
        ])
        return window
    }

    /// Detects newly started games and sends push-to-start APNS notifications
    /// to users who have those teams as favorites.
    private func sendPushToStartForNewGames(
        newResult: LiveScore,
        previousResult: LiveScore?,
        context: Queues.QueueContext,
        isDebug: Bool
    ) async {
        let newlyStarted = Self.detectNewlyStartedGames(newResult: newResult, previousResult: previousResult)
        guard !newlyStarted.isEmpty else { return }
        Self.logger.info("Detected \(newlyStarted.count) newly started games for push-to-start")

        // Per-game "went live" record so we can later answer "how late did ESPN flip
        // this game to `in` relative to its scheduled kickoff?" without guessing.
        // The detection is minutely, so this server timestamp ≈ ESPN's flip time ±60s.
        let now = context.application.appClock.now
        for game in newlyStarted {
            let lateByMin = game.isoDate.map { now.timeIntervalSince($0) / 60 }
            Self.logger.info("Game went live", metadata: [
                "eventID": "\(game.idEvent ?? "?")",
                "league": "\(game.idLeague ?? "?")",
                "match": "\(game.strHomeTeam) vs \(game.strAwayTeam)",
                "scheduledKickoff": "\(game.strTimestamp ?? "?")",
                "espnFlippedLateByMin": "\(lateByMin.map { String(format: "%.1f", $0) } ?? "?")",
            ])
        }

        guard context.application.storage[APNSConfiguredKey.self] == true else {
            Self.logger.warning("APNS not configured — skipping push-to-start notifications")
            return
        }

        await Self.runPushToStartPhase(
            newlyStarted: newlyStarted,
            kv: context.application.kv,
            apns: context.application.apnsSending,
            clock: context.application.appClock,
            isDebug: isDebug,
            logger: Self.logger,
            metrics: context.application.pushMetrics,
            telemetry: context.application.telemetry
        )
    }

    // MARK: - Testable helpers

    /// Pure transition detection — a game is "newly started" when its `strStatus`
    /// first flips to `"in"` between the previous tick and this one. Kept static
    /// + pure so the branch is trivially unit-testable with two LiveScore inputs.
    static func detectNewlyStartedGames(newResult: LiveScore, previousResult: LiveScore?) -> [Game] {
        let allNewGames = collectAllGamesFromLiveScore(newResult)
        let allPreviousGames = collectAllGamesFromLiveScore(previousResult)

        let previousIDs = Set(
            allPreviousGames
                .filter { !$0.hasDoneStatus && $0.strStatus == "in" }
                .compactMap(\.idEvent)
        )
        return allNewGames.filter { game in
            guard let eventID = game.idEvent,
                  game.strStatus == "in",
                  !previousIDs.contains(eventID) else { return false }
            return true
        }
    }

    /// Static equivalent of `collectAllGames(from:)` — needed because the transition
    /// detection logic is also static. Keeping them in lockstep matters: a divergence
    /// here would break the push-to-start pipeline silently.
    static func collectAllGamesFromLiveScore(_ liveScore: LiveScore?) -> [Game] {
        guard let liveScore else { return [] }
        var games: [Game] = []
        games.append(contentsOf: liveScore.nba?.events ?? [])
        games.append(contentsOf: liveScore.mlb?.events ?? [])
        games.append(contentsOf: liveScore.soccer?.events ?? [])
        games.append(contentsOf: liveScore.nfl?.events ?? [])
        games.append(contentsOf: liveScore.nhl?.events ?? [])
        games.append(contentsOf: liveScore.golf?.events ?? [])
        games.append(contentsOf: liveScore.tennis?.events ?? [])
        games.append(contentsOf: liveScore.racing?.events ?? [])
        return games
    }

    /// Scans push-to-start registrations, matches newly-started games against
    /// favorites and auto-follow event IDs, and dispatches pushes through the
    /// APNSSending seam. Deduplicates via `SentPushToStart-{token}-{eventID}` keys.
    ///
    /// Iterates both production (`PushToStart-`) and sandbox (`debug-PushToStart-`)
    /// keyspaces unconditionally so a single server can serve both Xcode dev
    /// devices and TestFlight / App Store users at the same time.
    static func runPushToStartPhase(
        newlyStarted: [Game],
        kv: KeyValueStore,
        apns: APNSSending,
        clock: AppClock,
        isDebug: Bool,
        logger: Logger,
        metrics: PushMetrics? = nil,
        telemetry: Telemetry? = nil
    ) async {
        let envPrefixes: [(prefix: String, env: APNSEnvironment)] = [
            ("PushToStartByInstall-", .production),
            ("debug-PushToStartByInstall-", .sandbox),
        ]

        let newlyStartedIDs = Set(newlyStarted.compactMap(\.idEvent))

        let (teamShortByID, teamNameByID, teamShortByName) = await loadTeamAbbreviationTables(kv: kv, isDebug: isDebug)

        for spec in envPrefixes {
            let installKeys = (try? await kv.scanKeys(matching: "\(spec.prefix)*")) ?? []
            if !installKeys.isEmpty {
                logger.info("Scanning \(installKeys.count) push-to-start installs [\(spec.env.rawValue)]")
            }

            for installKey in installKeys {
                guard let install = try? await kv.getJSON(installKey, as: PushToStartInstall.self) else { continue }
                let favoritesSet = Set(install.favorites)
                let eventIDsSet = Set(install.eventIDs)

                // Per-install dedup of matches: a game on the favorites list AND
                // the auto-follow list must only fire once. Use a set of eventIDs.
                var matchedEventIDs = Set<String>()
                for game in newlyStarted {
                    guard let eventID = game.idEvent else { continue }
                    let isFavoriteMatch = favoritesSet.contains(game.strHomeTeam) || favoritesSet.contains(game.strAwayTeam)
                    let isEventIDMatch = eventIDsSet.contains(eventID) && newlyStartedIDs.contains(eventID)
                    guard isFavoriteMatch || isEventIDMatch else { continue }
                    guard matchedEventIDs.insert(eventID).inserted else { continue }

                    let via = isFavoriteMatch ? (isEventIDMatch ? "favorites+eventID" : "favorites") : "eventID"
                    logger.info("Matching \(game.strHomeTeam) vs \(game.strAwayTeam) → install \(install.installID.prefix(8))... token \(install.token.prefix(8))... [\(spec.env.rawValue)] (via \(via))")
                    await sendPushToStartNotification(
                        game: game,
                        token: install.token,
                        environment: spec.env,
                        kv: kv,
                        apns: apns,
                        clock: clock,
                        logger: logger,
                        metrics: metrics,
                        telemetry: telemetry,
                        teamShortByID: teamShortByID,
                        teamNameByID: teamNameByID,
                        teamShortByName: teamShortByName
                    )
                }
            }
        }
    }

    /// Loads the cached teams payload and builds the three lookup tables
    /// push-to-start needs for compact-island abbreviations: ID→short (primary),
    /// ID→name (cross-sport collision validation), and name→short (fallback when
    /// the ID is wrong). Shared by the transition path and the already-live path.
    static func loadTeamAbbreviationTables(
        kv: KeyValueStore,
        isDebug: Bool
    ) async -> (shortByID: [String: String], nameByID: [String: String], shortByName: [String: String]) {
        let teamsKey = RedisEndpoint.teams.getValue(isDebug: isDebug).rawValue
        var teamShortByID: [String: String] = [:]
        var teamNameByID: [String: String] = [:]
        var teamShortByName: [String: String] = [:]
        if let teams = try? await kv.getJSON(teamsKey, as: [Team].self) {
            for team in teams {
                guard let id = team.idTeam else { continue }
                if let name = team.strTeam {
                    teamNameByID[id] = name
                    if let short = team.strTeamShort, !short.isEmpty {
                        teamShortByID[id] = short
                        teamShortByName[name] = short
                    }
                } else if let short = team.strTeamShort, !short.isEmpty {
                    teamShortByID[id] = short
                }
            }
        }
        return (teamShortByID, teamNameByID, teamShortByName)
    }

    /// Fires push-to-start for games that are ALREADY live when a single install
    /// registers. The scheduled path only sends on the not-`in`→`in` transition,
    /// so a user who taps "Follow" (or "Follow World Cup") mid-match would get no
    /// Live Activity until the next kickoff. Called inline from the register route.
    ///
    /// Matches the install's favorites / auto-follow event IDs against the live
    /// scoreboard and sends a start for each. The shared
    /// `SentPushToStart-{token}-{eventID}` claim inside `sendPushToStartNotification`
    /// dedupes against the transition path, so this never double-fires.
    static func sendStartsForAlreadyLiveGames(
        install: PushToStartInstall,
        liveGames: [Game],
        environment: APNSEnvironment,
        kv: KeyValueStore,
        apns: APNSSending,
        clock: AppClock,
        isDebug: Bool,
        logger: Logger,
        metrics: PushMetrics? = nil,
        telemetry: Telemetry? = nil
    ) async {
        let favoritesSet = Set(install.favorites)
        let eventIDsSet = Set(install.eventIDs)
        guard !favoritesSet.isEmpty || !eventIDsSet.isEmpty else { return }

        let liveNow = liveGames.filter { $0.strStatus == "in" && !$0.hasDoneStatus }
        guard !liveNow.isEmpty else { return }

        let (teamShortByID, teamNameByID, teamShortByName) = await loadTeamAbbreviationTables(kv: kv, isDebug: isDebug)

        var matchedEventIDs = Set<String>()
        for game in liveNow {
            guard let eventID = game.idEvent else { continue }
            let isFavoriteMatch = favoritesSet.contains(game.strHomeTeam) || favoritesSet.contains(game.strAwayTeam)
            let isEventIDMatch = eventIDsSet.contains(eventID)
            guard isFavoriteMatch || isEventIDMatch else { continue }
            guard matchedEventIDs.insert(eventID).inserted else { continue }

            let via = isFavoriteMatch ? (isEventIDMatch ? "favorites+eventID" : "favorites") : "eventID"
            logger.info("Already-live match \(game.strHomeTeam) vs \(game.strAwayTeam) → install \(install.installID.prefix(8))... [\(environment.rawValue)] (via \(via))")
            await sendPushToStartNotification(
                game: game,
                token: install.token,
                environment: environment,
                kv: kv,
                apns: apns,
                clock: clock,
                logger: logger,
                metrics: metrics,
                telemetry: telemetry,
                teamShortByID: teamShortByID,
                teamNameByID: teamNameByID,
                teamShortByName: teamShortByName
            )
        }
    }

    /// Sends a push-to-start APNS notification, deduplicating via
    /// `SentPushToStart-{token}-{eventID}` keys (8h TTL). Cleans up stale tokens
    /// when APNS reports the token as dead.
    ///
    /// `environment` selects which APNS gateway to send to (sandbox vs production)
    /// and which Redis keyspace to read/delete from for dedup and cleanup.
    static func sendPushToStartNotification(
        game: Game,
        token: String,
        environment: APNSEnvironment,
        kv: KeyValueStore,
        apns: APNSSending,
        clock: AppClock,
        logger: Logger,
        metrics: PushMetrics? = nil,
        telemetry: Telemetry? = nil,
        teamShortByID: [String: String] = [:],
        teamNameByID: [String: String] = [:],
        teamShortByName: [String: String] = [:]
    ) async {
        guard let eventID = game.idEvent else { return }
        let homeTeam = game.strHomeTeam
        let awayTeam = game.strAwayTeam
        // Validate the ID-based lookup by name to guard against cross-sport ID collisions
        // (e.g. ESPN NBA ID 18 ≠ ESPN NHL ID 18 — a wrong translation would return "LAC"
        // for the Knicks). Fall back to name-based lookup if the ID resolves to a different team.
        let homeTeamShort = game.idHomeTeam.flatMap { id -> String? in
            guard teamNameByID[id] == homeTeam else { return nil }
            return teamShortByID[id]
        } ?? teamShortByName[homeTeam]
        let awayTeamShort = game.idAwayTeam.flatMap { id -> String? in
            guard teamNameByID[id] == awayTeam else { return nil }
            return teamShortByID[id]
        } ?? teamShortByName[awayTeam]

        // Dedup key namespacing follows the registration's environment so a
        // sandbox token and a prod token watching the same event don't share
        // dedup state (one's success would silence the other).
        //
        // Atomic SET NX EX: only one caller — across all server instances — wins
        // the claim. Losers skip silently. Closes the TOCTOU window the previous
        // exists() → setString() pair had between multi-replica deploys.
        let sentKey = RedisEndpoint.sentPushToStart(token, eventID).getValue(isDebug: environment == .sandbox).rawValue
        let claimed = (try? await kv.setIfAbsent(sentKey, value: "1", ttl: 60 * 60 * 8)) ?? false
        guard claimed else {
            logger.info("Lost push-to-start claim for \(eventID) → \(token.prefix(8))... — skipping")
            await metrics?.recordDedup(hit: true)
            return
        }
        await metrics?.recordDedup(hit: false)

        let attributes = LiveSportAttributes(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            eventID: eventID,
            homeTeamShort: homeTeamShort,
            awayTeamShort: awayTeamShort
        )
        let contentState = ContentState(
            homeScore: Int(game.intHomeScore ?? "") ?? 0,
            awayScore: Int(game.intAwayScore ?? "") ?? 0,
            status: game.strStatus,
            progress: game.strProgress,
            lastPlay: game.lastPlay
        )

        do {
            // Send on the registered gateway; on badDeviceToken, retry the opposite
            // one. A device that registered under the wrong APNS environment (e.g. a
            // sandbox token labeled production) would otherwise never receive a start.
            let (_, delivered) = try await sendWithEnvironmentFallback(primary: environment) { env in
                try await apns.sendPushToStart(
                    deviceToken: token,
                    appID: "com.KomodoLLC.SportsCal",
                    attributes: attributes,
                    contentState: contentState,
                    alertTitle: "\(homeTeam) vs \(awayTeam)",
                    alertBody: "Game is starting now!",
                    timestamp: Int(clock.now.timeIntervalSince1970),
                    environment: env
                )
            }
            if delivered != environment {
                logger.warning("push-to-start for \(eventID) delivered on \(delivered.rawValue) after \(environment.rawValue) returned badDeviceToken — token \(token.prefix(8))... registered under the wrong APNS environment")
                await telemetry?.warning("pushtostart.env_corrected", [
                    "registered": environment.rawValue,
                    "delivered": delivered.rawValue,
                    "event": eventID,
                ])
            }
            logger.info("Sent push-to-start for \(homeTeam) vs \(awayTeam) to token \(token.prefix(8))... [\(delivered.rawValue)]")
            await metrics?.recordSend(kind: .start)
            await telemetry?.info("pushtostart.sent", ["event": eventID, "env": delivered.rawValue])
        } catch let sendError as APNSSendError {
            logger.error("Failed to send push-to-start for event \(eventID) [\(environment.rawValue)]: \(sendError.reason.rawValue) \(sendError.underlying ?? "")")
            await metrics?.recordError(sendError.reason)
            await telemetry?.error("pushtostart.failed", ["event": eventID, "reason": sendError.reason.rawValue])
            if sendError.isStaleToken {
                // Both gateways rejected the token → genuinely dead. Remove the
                // install across the matching keyspace.
                logger.warning("Removing stale push-to-start token \(token.prefix(8))... [\(environment.rawValue)]")
                // Reverse-index lookup gives us the installID so we can delete the
                // install record without iterating every install in the namespace.
                let indexKey = RedisEndpoint.pushToStartTokenIndex(token).getValue(isDebug: environment == .sandbox).rawValue
                var toDelete: [String] = [indexKey]
                if let installID = try? await kv.getString(indexKey) {
                    let installKey = RedisEndpoint.pushToStartByInstall(installID).getValue(isDebug: environment == .sandbox).rawValue
                    toDelete.append(installKey)
                }
                // Also clear this token's dedup claims (both env namespaces) so a
                // re-registration of the SAME token isn't blocked from retrying for
                // the 8h claim TTL — the bug that left re-registered devices stuck.
                for prefix in ["SentPushToStart-", "debug-SentPushToStart-"] {
                    if let claims = try? await kv.scanKeys(matching: "\(prefix)\(token)-*") {
                        toDelete.append(contentsOf: claims)
                    }
                }
                _ = try? await kv.delete(toDelete)
                await metrics?.recordCleanup(reason: sendError.reason.rawValue)
                // A registration removed here is the long-TTL downside materializing:
                // a token that rotated or died without the client re-registering.
                // Watch this against `pushtostart.token_rotated` to tune the TTL.
                await telemetry?.warning("pushtostart.token_cleaned", [
                    "reason": sendError.reason.rawValue,
                    "env": environment.rawValue,
                ])
            } else {
                // Transient: release the claim so the next cycle can retry rather
                // than waiting out the 8h TTL with no actual notification delivered.
                _ = try? await kv.delete([sentKey])
            }
        } catch {
            logger.error("Failed to send push-to-start for event \(eventID) [\(environment.rawValue)]: \(error)")
            await metrics?.recordError(.other)
            await telemetry?.error("pushtostart.failed", ["event": eventID, "reason": "other"])
            _ = try? await kv.delete([sentKey])
        }
    }

    /// Collects all games from all sports in a LiveScore
    private func collectAllGames(from liveScore: LiveScore?) -> [Game] {
        guard let liveScore else { return [] }
        var games: [Game] = []
        games.append(contentsOf: liveScore.nba?.events ?? [])
        games.append(contentsOf: liveScore.mlb?.events ?? [])
        games.append(contentsOf: liveScore.soccer?.events ?? [])
        games.append(contentsOf: liveScore.nfl?.events ?? [])
        games.append(contentsOf: liveScore.nhl?.events ?? [])
        games.append(contentsOf: liveScore.golf?.events ?? [])
        games.append(contentsOf: liveScore.tennis?.events ?? [])
        games.append(contentsOf: liveScore.racing?.events ?? [])
        return games
    }

    /// Translates ESPN team IDs to TheSportsDB IDs in all games within a LiveScore
    private func translateTeamIDs(in liveScore: LiveScore, using mapping: [String: String]) -> LiveScore {
        // Keys in the mapping are sport-scoped (e.g. "nba:18") to prevent cross-sport
        // collisions where ESPN reuses the same numeric ID across different sports.
        func translateEvents(_ events: [Game], bucket: String) -> [Game] {
            events.map { game in
                let homeID = game.idHomeTeam.flatMap { mapping["\(bucket):\($0)"] } ?? game.idHomeTeam
                let awayID = game.idAwayTeam.flatMap { mapping["\(bucket):\($0)"] } ?? game.idAwayTeam
                guard homeID != game.idHomeTeam || awayID != game.idAwayTeam else { return game }
                return game.updated(idHomeTeam: homeID, idAwayTeam: awayID)
            }
        }

        return LiveScore(
            nba: liveScore.nba.map { LiveEvent(events: translateEvents($0.events, bucket: "nba")) },
            mlb: liveScore.mlb.map { LiveEvent(events: translateEvents($0.events, bucket: "mlb")) },
            soccer: liveScore.soccer.map { LiveEvent(events: translateEvents($0.events, bucket: "soccer")) },
            nfl: liveScore.nfl.map { LiveEvent(events: translateEvents($0.events, bucket: "nfl")) },
            nhl: liveScore.nhl.map { LiveEvent(events: translateEvents($0.events, bucket: "nhl")) },
            golf: liveScore.golf.map { LiveEvent(events: translateEvents($0.events, bucket: "golf")) },
            tennis: liveScore.tennis.map { LiveEvent(events: translateEvents($0.events, bucket: "tennis")) },
            racing: liveScore.racing.map { LiveEvent(events: translateEvents($0.events, bucket: "racing")) }
        )
    }
    
    // MARK: - Schedule Merge

    /// Merges ESPN live data into the TheSportsDB-sourced schedule, updating scores/statuses
    /// while preserving TheSportsDB identifiers and scheduled start times.
    func mergeESPNIntoSchedule(schedule: LiveScore, espn: LiveScore, resolver: TeamAliasResolver) -> LiveScore {
        LiveScore(
            nba: mergeSportEvents(schedule: schedule.nba, espn: espn.nba, resolver: resolver),
            mlb: mergeSportEvents(schedule: schedule.mlb, espn: espn.mlb, resolver: resolver),
            soccer: mergeSportEvents(schedule: schedule.soccer, espn: espn.soccer, resolver: resolver),
            nfl: mergeSportEvents(schedule: schedule.nfl, espn: espn.nfl, resolver: resolver),
            nhl: mergeSportEvents(schedule: schedule.nhl, espn: espn.nhl, resolver: resolver),
            golf: mergeSportEvents(schedule: schedule.golf, espn: espn.golf, resolver: resolver),
            tennis: mergeSportEvents(schedule: schedule.tennis, espn: espn.tennis, resolver: resolver),
            racing: mergeSportEvents(schedule: schedule.racing, espn: espn.racing, resolver: resolver),
            // Ridealong enrichments live on the schedule blob; carry them through or
            // every live tick wipes them until the hourly enrichment jobs re-attach
            // (symptom: Bracket CTA / F1 standings flicker in and out on the client).
            f1Standings: schedule.f1Standings ?? espn.f1Standings,
            worldCup: schedule.worldCup ?? espn.worldCup
        )
    }

    /// Normalizes team names to handle abbreviation differences
    /// (e.g., "LA Clippers" → "los angeles clippers", "NY Knicks" → "new york knicks")
    func normalizeTeamName(_ name: String) -> String {
        var result = name.lowercased()
        // Common city abbreviations — order matters (longer matches first)
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
        // Also normalize FC/SC positioning for soccer (e.g., "FC Barcelona" vs "Barcelona FC")
        result = result.replacingOccurrences(of: " fc", with: "")
        result = result.replacingOccurrences(of: "fc ", with: "")
        result = result.replacingOccurrences(of: " sc", with: "")
        result = result.replacingOccurrences(of: "sc ", with: "")
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Merges ESPN events into a single sport's schedule events.
    /// Matches by team IDs + day, falls back to team names + day, normalized names + day,
    /// alias-aware canonical key + day, or event name for individual sports.
    func mergeSportEvents(schedule: LiveEvent?, espn: LiveEvent?, resolver: TeamAliasResolver) -> LiveEvent? {
        guard let schedule else { return espn }
        guard let espn, !espn.events.isEmpty else { return schedule }

        // Build ESPN lookup dictionaries. Values are ARRAYS: the same two teams can
        // meet twice on one UTC day (an MLB evening game lands after UTC midnight on
        // the same UTC date as the next afternoon's game, plus true doubleheaders),
        // so a day key alone is ambiguous — the caller disambiguates by kickoff time.
        // Key: (lowercased homeTeamID, lowercased awayTeamID, dayString)
        var espnByTeamIDs: [String: [Game]] = [:]
        // Key: (lowercased homeTeamName, lowercased awayTeamName, dayString)
        var espnByTeamNames: [String: [Game]] = [:]
        // Key: (normalized homeTeamName, normalized awayTeamName, dayString)
        var espnByNormalizedNames: [String: [Game]] = [:]
        // Key: alias-resolved canonical key (catches "PSG" ≡ "Paris Saint-Germain" etc.)
        var espnByCanonicalKey: [String: [Game]] = [:]
        // Key: lowercased event/tournament name (for individual sports)
        var espnByEventName: [String: Game] = [:]

        for game in espn.events {
            let day = dayString(from: game)

            if let homeID = game.idHomeTeam, let awayID = game.idAwayTeam,
               !homeID.isEmpty, !awayID.isEmpty {
                let key = "\(homeID.lowercased())|\(awayID.lowercased())|\(day)"
                espnByTeamIDs[key, default: []].append(game)
            }

            let nameKey = "\(game.strHomeTeam.lowercased())|\(game.strAwayTeam.lowercased())|\(day)"
            espnByTeamNames[nameKey, default: []].append(game)

            let normalizedKey = "\(normalizeTeamName(game.strHomeTeam))|\(normalizeTeamName(game.strAwayTeam))|\(day)"
            espnByNormalizedNames[normalizedKey, default: []].append(game)

            let canonicalKey = resolver.dedupKey(home: game.strHomeTeam, away: game.strAwayTeam, leagueID: game.idLeague, day: day)
            espnByCanonicalKey[canonicalKey, default: []].append(game)

            // Golf/F1 carry the event name in strHomeTeam (strAwayTeam is "TBD"/leader), so a
            // name-only match is correct. Tennis matches are real head-to-heads — keying by home
            // player alone (no day) makes one live match match ALL of that player's season games,
            // bleeding today's score/status across every tournament. Exclude them; tennis still
            // matches legitimately via the team-name+day path above.
            if game.isIndividualSport && !game.isTennisMatch {
                espnByEventName[game.strHomeTeam.lowercased()] = game
            }
        }

        var matchedESPNIDs = Set<String>()

        // Days ESPN actively returned games for in this fetch. A cached entry
        // with an ESPN-style id (`401…`) on one of these days that ESPN no
        // longer reports is stale (rescheduled/removed upstream) and gets
        // pruned — otherwise these stick in the cache indefinitely.
        let espnReportedDays: Set<String> = Set(espn.events.map { dayString(from: $0) })

        let merged: [Game] = schedule.events.compactMap { scheduleGame -> Game? in
            let day = dayString(from: scheduleGame)
            var espnMatch: Game?

            // Primary: match by team IDs + day
            if let homeID = scheduleGame.idHomeTeam, let awayID = scheduleGame.idAwayTeam,
               !homeID.isEmpty, !awayID.isEmpty {
                let key = "\(homeID.lowercased())|\(awayID.lowercased())|\(day)"
                espnMatch = Self.closestByKickoff(espnByTeamIDs[key], to: scheduleGame)
            }

            // Fallback: match by team names + day
            if espnMatch == nil {
                let nameKey = "\(scheduleGame.strHomeTeam.lowercased())|\(scheduleGame.strAwayTeam.lowercased())|\(day)"
                espnMatch = Self.closestByKickoff(espnByTeamNames[nameKey], to: scheduleGame)
            }

            // Fallback: match by normalized team names + day (handles "LA" vs "Los Angeles" etc.)
            if espnMatch == nil {
                let normalizedKey = "\(normalizeTeamName(scheduleGame.strHomeTeam))|\(normalizeTeamName(scheduleGame.strAwayTeam))|\(day)"
                espnMatch = Self.closestByKickoff(espnByNormalizedNames[normalizedKey], to: scheduleGame)
            }

            // Fallback: alias-aware canonical key (handles "PSG" ≡ "Paris Saint-Germain" etc.).
            // When this is the path that finds the match, log it so we can see which alias
            // pairings are landing in production and grow the curated seed accordingly.
            if espnMatch == nil {
                let canonicalKey = resolver.dedupKey(home: scheduleGame.strHomeTeam, away: scheduleGame.strAwayTeam, leagueID: scheduleGame.idLeague, day: day)
                if let aliasMatch = Self.closestByKickoff(espnByCanonicalKey[canonicalKey], to: scheduleGame) {
                    Self.logger.warning("alias dedup: collapsed ESPN game", metadata: [
                        "espnHome": "\(aliasMatch.strHomeTeam)",
                        "espnAway": "\(aliasMatch.strAwayTeam)",
                        "scheduleHome": "\(scheduleGame.strHomeTeam)",
                        "scheduleAway": "\(scheduleGame.strAwayTeam)",
                        "league": "\(scheduleGame.idLeague ?? "-")",
                        "day": "\(day)"
                    ])
                    espnMatch = aliasMatch
                }
            }

            // Individual sports: match by event/tournament name (golf/F1 only — see build above).
            if espnMatch == nil && scheduleGame.isIndividualSport && !scheduleGame.isTennisMatch {
                espnMatch = espnByEventName[scheduleGame.strHomeTeam.lowercased()]
            }

            if let match = espnMatch {
                matchedESPNIDs.insert(match.id)
            }

            guard let espnGame = espnMatch else {
                if let id = scheduleGame.idEvent, id.hasPrefix("401"),
                   espnReportedDays.contains(day) {
                    return nil
                }
                return scheduleGame
            }

            // Merge: ESPN dynamic fields onto schedule identity fields
            // Don't take ESPN scores for pre-game events (ESPN returns "0" which
            // causes the client to show a score view instead of the game time)
            let isPreGame = espnGame.strStatus == "pre"
            return Game(
                idLiveScore: scheduleGame.idLiveScore,
                idEvent: scheduleGame.idEvent,
                strSport: nil,
                idLeague: scheduleGame.idLeague,
                strLeague: nil,
                idHomeTeam: scheduleGame.idHomeTeam,
                idAwayTeam: scheduleGame.idAwayTeam,
                strHomeTeam: espnGame.strHomeTeam,
                strAwayTeam: espnGame.strAwayTeam,
                strHomeTeamBadge: scheduleGame.strHomeTeamBadge ?? espnGame.strHomeTeamBadge,
                strAwayTeamBadge: scheduleGame.strAwayTeamBadge ?? espnGame.strAwayTeamBadge,
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
                leaderboardEntries: espnGame.leaderboardEntries ?? scheduleGame.leaderboardEntries,
                sessions: espnGame.sessions ?? scheduleGame.sessions,
                venueName: scheduleGame.venueName ?? espnGame.venueName,
                homeTeamColor: espnGame.homeTeamColor ?? scheduleGame.homeTeamColor,
                awayTeamColor: espnGame.awayTeamColor ?? scheduleGame.awayTeamColor,
                homeRecord: espnGame.homeRecord ?? scheduleGame.homeRecord,
                awayRecord: espnGame.awayRecord ?? scheduleGame.awayRecord,
                circuitInfo: scheduleGame.circuitInfo ?? espnGame.circuitInfo,
                legDisplay: espnGame.legDisplay ?? scheduleGame.legDisplay,
                aggregateScore: espnGame.aggregateScore ?? scheduleGame.aggregateScore,
                homeSeed: espnGame.homeSeed ?? scheduleGame.homeSeed,
                awaySeed: espnGame.awaySeed ?? scheduleGame.awaySeed,
                // Preserve tournament identity from the structured schedule — without this the
                // merge strips tournamentName/round off every matched tennis game, collapsing
                // browse back into the two flat "ATP Tour"/"WTA Tour" buckets.
                tournamentName: scheduleGame.tournamentName ?? espnGame.tournamentName,
                round: scheduleGame.round ?? espnGame.round,
                homeInjuries: scheduleGame.homeInjuries ?? espnGame.homeInjuries,
                awayInjuries: scheduleGame.awayInjuries ?? espnGame.awayInjuries,
                raceTiming: scheduleGame.raceTiming ?? espnGame.raceTiming,
                playoff: espnGame.playoff ?? scheduleGame.playoff
            )
        }

        // Append ESPN-only games (no TheSportsDB match),
        // but skip games that already exist in the schedule by normalized team+day
        // or by alias-resolved canonical key (catches "LA Clippers" vs "Los Angeles
        // Clippers", "PSG" vs "Paris Saint-Germain", etc.). Day keys hold kickoff
        // times so a second same-teams game on one UTC day isn't wrongly dropped.
        var scheduleByDay: [String: [Date?]] = [:]
        var scheduleCanonicalKeys: [String: [Date?]] = [:]
        for game in schedule.events {
            let day = dayString(from: game)
            let home = normalizeTeamName(game.strHomeTeam)
            let away = normalizeTeamName(game.strAwayTeam)
            let date = game.isoDate ?? game.getDate()
            scheduleByDay["\(home)|\(away)|\(day)", default: []].append(date)
            scheduleByDay["\(away)|\(home)|\(day)", default: []].append(date)
            scheduleCanonicalKeys[resolver.dedupKey(home: game.strHomeTeam, away: game.strAwayTeam, leagueID: game.idLeague, day: day), default: []].append(date)
        }

        // Same-fixture test against the schedule rows behind a key: within the
        // kickoff window (or either side undated — the conservative legacy skip).
        func alreadyScheduled(_ dates: [Date?]?, _ game: Game) -> Bool {
            guard let dates, !dates.isEmpty else { return false }
            guard let gameDate = game.isoDate ?? game.getDate() else { return true }
            return dates.contains { scheduled in
                guard let scheduled else { return true }
                return abs(scheduled.timeIntervalSince(gameDate)) <= Self.sameFixtureWindow
            }
        }

        let unmatchedESPN = espn.events.filter { game in
            guard !matchedESPNIDs.contains(game.id) else { return false }
            let day = dayString(from: game)
            let home = normalizeTeamName(game.strHomeTeam)
            let away = normalizeTeamName(game.strAwayTeam)
            let key = "\(home)|\(away)|\(day)"
            if alreadyScheduled(scheduleByDay[key], game) { return false }
            let canonicalKey = resolver.dedupKey(home: game.strHomeTeam, away: game.strAwayTeam, leagueID: game.idLeague, day: day)
            if alreadyScheduled(scheduleCanonicalKeys[canonicalKey], game) {
                Self.logger.warning("alias dedup: dropped unmatched ESPN game", metadata: [
                    "espnHome": "\(game.strHomeTeam)",
                    "espnAway": "\(game.strAwayTeam)",
                    "league": "\(game.idLeague ?? "-")",
                    "day": "\(day)"
                ])
                return false
            }
            return true
        }

        return LiveEvent(events: merged + unmatchedESPN)
    }

    /// Two records within this window count as the same fixture; farther apart they
    /// are different games (last night's post-UTC-midnight game vs. today's, or the
    /// two halves of a doubleheader — real games are never twice within 3h).
    static let sameFixtureWindow: TimeInterval = 3 * 3600

    /// Resolves a day-keyed lookup that may hold several same-teams games: picks the
    /// candidate closest to the schedule game's kickoff, refusing anything beyond
    /// `sameFixtureWindow`. Without this, a finished game's ESPN result gets overlaid
    /// onto the same matchup's later game on the same UTC day — users see "already
    /// finished" games that haven't started. Undated candidates keep legacy behavior.
    /// (Static: also used by ScheduleUpdateJob.mergeEnrichment, which had the same bug.)
    static func closestByKickoff(_ candidates: [Game]?, to scheduleGame: Game) -> Game? {
        guard let candidates, !candidates.isEmpty else { return nil }
        guard let target = scheduleGame.isoDate ?? scheduleGame.getDate() else { return candidates.first }
        var best: (game: Game, distance: TimeInterval)?
        for candidate in candidates {
            // Undated candidate: can't disambiguate — accept it (pre-fix behavior).
            guard let date = candidate.isoDate ?? candidate.getDate() else { return candidate }
            let distance = abs(date.timeIntervalSince(target))
            if best == nil || distance < best!.distance { best = (candidate, distance) }
        }
        guard let best, best.distance <= Self.sameFixtureWindow else { return nil }
        return best.game
    }

    /// Extracts a "YYYY-MM-DD" day string from a Game for same-day matching.
    func dayString(from game: Game) -> String {
        if let date = game.isoDate {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(secondsFromGMT: 0)
            return df.string(from: date)
        }
        // Fallback: extract from strTimestamp prefix
        if let ts = game.strTimestamp, ts.count >= 10 {
            return String(ts.prefix(10))
        }
        return ""
    }

    func returnUpdatedEvents(events: [Game], espnEvents: [Game]) -> LiveEvent {
        let newEvents: [Game] = espnEvents.compactMap { event in
            if let foundEvent = events.first(where: {$0.strHomeTeam == event.strHomeTeam && $0.strAwayTeam == event.strAwayTeam}) {
                // Only include essential fields - strSport/strLeague are computed from idLeague
                // Deprecated fields removed: strPlayer, idPlayer, intEventScore, intEventScoreTotal, strEventTime, dateEvent, updated
                return Game(idLiveScore: foundEvent.idLiveScore, idEvent: foundEvent.idEvent, strSport: nil, idLeague: foundEvent.idLeague, strLeague: nil, idHomeTeam: foundEvent.idHomeTeam, idAwayTeam: foundEvent.idAwayTeam, strHomeTeam: foundEvent.strHomeTeam, strAwayTeam: foundEvent.strAwayTeam, strHomeTeamBadge: foundEvent.strHomeTeamBadge, strAwayTeamBadge: foundEvent.strAwayTeamBadge, intHomeScore: event.intHomeScore, intAwayScore: event.intAwayScore, strStatus: event.strStatus, strProgress: event.strProgress, strTimestamp: foundEvent.strTimestamp, lastPlay: event.lastPlay, homeLinescores: event.homeLinescores, awayLinescores: event.awayLinescores, homeLeaders: event.homeLeaders, awayLeaders: event.awayLeaders, isCompleted: event.isCompleted, isoDate: Game.getDate(timestamp: foundEvent.strTimestamp), leaderboardEntries: event.leaderboardEntries, sessions: event.sessions, venueName: event.venueName, homeTeamColor: event.homeTeamColor, awayTeamColor: event.awayTeamColor, homeRecord: event.homeRecord, awayRecord: event.awayRecord, legDisplay: event.legDisplay, aggregateScore: event.aggregateScore, homeSeed: event.homeSeed, awaySeed: event.awaySeed, tournamentName: foundEvent.tournamentName ?? event.tournamentName, round: foundEvent.round ?? event.round, playoff: event.playoff)
            } else {
                return event
            }
        }
        if newEvents.isEmpty {
            return LiveEvent(events: espnEvents)
        }

        return LiveEvent(events: newEvents)
    }
}
extension Game {
    func getDate() -> Date? {
        DateFormatters.backupISOFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        DateFormatters.backupISOFormatter.timeZone = .init(secondsFromGMT: 0)
        guard let timestamp = strTimestamp else { return nil }
        if let date = DateFormatters.isoFormatter.date(from: timestamp) {
            return date
        }
        if let date = DateFormatters.backupISOFormatter.date(from: timestamp) {
            return date
        }
        DateFormatters.backupISOFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let date = DateFormatters.backupISOFormatter.date(from: timestamp) {
            return date
        }
        return nil
    }
    static func getDate(timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        DateFormatters.backupISOFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        DateFormatters.backupISOFormatter.timeZone = .init(secondsFromGMT: 0)
        if let date = DateFormatters.isoFormatter.date(from: timestamp) {
            return date
        }
        if let date = DateFormatters.backupISOFormatter.date(from: timestamp) {
            return date
        }
        DateFormatters.backupISOFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let date = DateFormatters.backupISOFormatter.date(from: timestamp) {
            return date
        }
        return nil
    }
}
