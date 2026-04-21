//
//  File.swift
//  
//
//  Created by Umar Haroon on 2/23/23.
//

import Foundation
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

        // Only fetch live scores if there are games happening or starting soon
        let shouldFetchLive = await Integrator.hasLiveOrUpcomingGames(
            redis: context.application.redis,
            isDebug: isDebug
        )

        if !shouldFetchLive {
            Self.logger.info("No live or upcoming games — skipping ESPN live score fetch")
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

        Self.logger.info("Fetching ESPN live scores")
        let espnResult = await Integrator.getESPNLiveScore(context.application.client)

        // Fire per-event play-by-play enrichment (NBA/NFL/NHL/MLB).
        // Side-effect only: writes to Redis at PBP-{eventID}. Must run against the fresh
        // `espnResult` because `lastPlayScoreboardID` is lost when games are rebuilt downstream.
        await enrichWithPlays(from: espnResult, context: context, isDebug: isDebug)

        let latestLiveResult = try await context.application.redis.get(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug), asJSON: LiveScore.self)

        // Load ESPN-ID → TheSportsDB-ID mapping for team ID translation
        let mappingKey: RedisKey = isDebug ? "debug-ESPN-ID-Map" : "ESPN-ID-Map"
        let espnToTSDB = try await context.application.redis.get(mappingKey, asJSON: [String: String].self) ?? [:]

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

        // Translate ESPN team IDs to TheSportsDB IDs in all live games
        // This must happen BEFORE merging NCAA games, since ESPN IDs are per-sport
        // and NCAA team IDs can collide with NBA team IDs in the mapping
        if !espnToTSDB.isEmpty {
            newResult = newResult.map { translateTeamIDs(in: $0, using: espnToTSDB) }
        }

        // Merge NCAA Tournament into basketball AFTER ID translation to avoid
        // NCAA ESPN IDs being incorrectly mapped to NBA TheSportsDB IDs
        if let ncaaScoreboard = try? await Integrator.getESPNScoreboard(for: .ncaaMBBTournament, context.application.client),
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
        if let wnbaScoreboard = try? await Integrator.getESPNScoreboard(for: .wnba, context.application.client),
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

        // Merge ESPN data into cached schedule so /schedules reflects live scores.
        // Also pull forward a rolling window of upcoming postseason days so games
        // scheduled for the next few days surface series context (round, Game N, wins).
        if let newResult {
            let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
            if let schedule = try? await context.application.redis.get(scheduleKey, asJSON: LiveScore.self) {
                let window = await fetchPostseasonWindowIfStale(context: context, isDebug: isDebug, daysAhead: 7)
                let enriched = newResult.merging(with: window)
                let updated = mergeESPNIntoSchedule(schedule: schedule, espn: enriched)
                if updated != schedule {
                    try? await context.application.redis.set(scheduleKey, toJSON: updated)
                    Self.logger.info("Schedule updated with ESPN live data")
                }
            }
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

    // MARK: - Future postseason window

    /// Fetches ESPN scoreboards for the next `daysAhead` days for each playoff-eligible
    /// team league, filters to games ESPN has flagged as postseason, and caches the result.
    /// Refreshed every 60 minutes — ESPN's series metadata doesn't change frequently enough
    /// to justify fetching 28+ scoreboards per minute.
    private func fetchPostseasonWindowIfStale(
        context: Queues.QueueContext,
        isDebug: Bool,
        daysAhead: Int
    ) async -> LiveScore {
        let cacheKey = RedisEndpoint.ESPN.postseasonWindow.getValue(isDebug: isDebug)
        let updateKey = RedisEndpoint.ESPN.postseasonWindowLastUpdate.getValue(isDebug: isDebug)

        // Use cached window if it's still fresh (<1h old).
        if let lastUpdate = try? await context.application.redis.get(updateKey, asJSON: Date.self),
           Date().timeIntervalSince(lastUpdate) < 60 * 60,
           let cached = try? await context.application.redis.get(cacheKey, asJSON: LiveScore.self) {
            return cached
        }

        let playoffLeagues: [(league: Leagues, sport: SportType)] = [
            (.nba, .basketball), (.nhl, .hockey), (.mlb, .mlb), (.nfl, .nfl)
        ]
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        df.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        var eventsBySport: [SportType: [Game]] = [:]
        for (league, sport) in playoffLeagues {
            var collected: [Game] = []
            for offset in 1...daysAhead {
                guard let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) else { continue }
                guard let ymd = Int(df.string(from: date)) else { continue }
                do {
                    let scoreboard = try await Integrator.getESPNScoreboard(for: league, context.application.client, dates: ymd)
                    guard let liveEvent = LiveEvent(events: scoreboard, league: league) else { continue }
                    // Only carry forward games that actually have structured playoff context.
                    collected.append(contentsOf: liveEvent.events.filter { $0.playoff != nil })
                } catch {
                    Self.logger.debug("Postseason window fetch failed", metadata: [
                        "league": "\(league)", "date": "\(ymd)", "error": "\(error)"
                    ])
                }
            }
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

        try? await context.application.redis.setex(cacheKey, toJSON: window, expirationInSeconds: 60 * 60)
        try? await context.application.redis.set(updateKey, toJSON: Date())
        let total = [window.nba, window.mlb, window.nfl, window.nhl].compactMap { $0?.events.count }.reduce(0, +)
        Self.logger.info("Postseason window refreshed", metadata: [
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
        // Collect all current live games
        let allNewGames = collectAllGames(from: newResult)
        let allPreviousGames = collectAllGames(from: previousResult)

        // Find games that are newly "in progress" (status == "in")
        let previousIDs = Set(allPreviousGames.filter { !$0.hasDoneStatus && $0.strStatus == "in" }.compactMap(\.idEvent))
        let newlyStarted = allNewGames.filter { game in
            guard let eventID = game.idEvent,
                  game.strStatus == "in",
                  !previousIDs.contains(eventID) else { return false }
            return true
        }

        guard !newlyStarted.isEmpty else { return }
        Self.logger.info("Detected \(newlyStarted.count) newly started games for push-to-start")

        guard context.application.storage[APNSConfiguredKey.self] == true else {
            Self.logger.warning("APNS not configured — skipping push-to-start notifications")
            return
        }

        // Scan all PushToStart-* registrations
        let keyPattern = isDebug ? "debug-PushToStart-*" : "PushToStart-*"
        guard let registrationKeys = try? await context.application.redis.send(command: "keys", with: [keyPattern.convertedToRESPValue()])
            .array?
            .compactMap({ $0.string })
            .map({ RedisKey($0) }),
              !registrationKeys.isEmpty else { return }

        let apnsClient = isDebug
            ? await context.application.apns.client(.development)
            : await context.application.apns.client(.production)
        let keyPrefix = isDebug ? "debug-PushToStart-" : "PushToStart-"

        let newlyStartedIDs = Set(newlyStarted.compactMap(\.idEvent))
        Self.logger.info("Scanning \(registrationKeys.count) push-to-start registrations")

        for registrationKey in registrationKeys {
            guard let favorites = try? await context.application.redis.get(registrationKey, asJSON: [String].self) else { continue }

            let favoritesSet = Set(favorites)
            let token = String(registrationKey.rawValue.dropFirst(keyPrefix.count))
            Self.logger.info("Registration \(token.prefix(8))... has \(favoritesSet.count) favorites")

            for game in newlyStarted {
                let homeTeam = game.strHomeTeam
                let awayTeam = game.strAwayTeam
                guard favoritesSet.contains(homeTeam) || favoritesSet.contains(awayTeam),
                      game.idEvent != nil else { continue }

                Self.logger.info("Matching \(homeTeam) vs \(awayTeam) → token \(token.prefix(8))... (via favorites)")
                try? await sendPushToStartNotification(
                    game: game, token: token, context: context, apnsClient: apnsClient, isDebug: isDebug
                )
            }
        }

        // Also check event-based auto-follow registrations
        let eventsKeyPattern = isDebug ? "debug-PushToStartEvents-*" : "PushToStartEvents-*"
        let eventsKeyPrefix = isDebug ? "debug-PushToStartEvents-" : "PushToStartEvents-"
        if let eventRegistrationKeys = try? await context.application.redis.send(command: "keys", with: [eventsKeyPattern.convertedToRESPValue()])
            .array?
            .compactMap({ $0.string })
            .map({ RedisKey($0) }),
           !eventRegistrationKeys.isEmpty {

            for registrationKey in eventRegistrationKeys {
                guard let eventIDs = try? await context.application.redis.get(registrationKey, asJSON: [String].self) else { continue }

                let token = String(registrationKey.rawValue.dropFirst(eventsKeyPrefix.count))
                let matchingIDs = Set(eventIDs).intersection(newlyStartedIDs)
                Self.logger.info("Event registration \(token.prefix(8))... has \(eventIDs.count) event IDs, \(matchingIDs.count) matches")

                for game in newlyStarted {
                    guard let eventID = game.idEvent,
                          matchingIDs.contains(eventID) else { continue }

                    Self.logger.info("Matching \(game.strHomeTeam) vs \(game.strAwayTeam) → token \(token.prefix(8))... (via eventID \(eventID))")
                    try? await sendPushToStartNotification(
                        game: game, token: token, context: context, apnsClient: apnsClient, isDebug: isDebug
                    )
                }
            }
        }
    }

    /// Sends a push-to-start APNS notification for a specific game to a specific token.
    /// Deduplicates using SentPushToStart Redis keys.
    private func sendPushToStartNotification(
        game: Game,
        token: String,
        context: Queues.QueueContext,
        apnsClient: some APNSClientProtocol,
        isDebug: Bool
    ) async throws {
        guard let eventID = game.idEvent else { return }
        let homeTeam = game.strHomeTeam
        let awayTeam = game.strAwayTeam

        // Check if we already sent this notification
        let sentKey = RedisEndpoint.sentPushToStart(token, eventID).getValue(isDebug: isDebug)
        let alreadySentCount = try? await context.application.redis.exists(sentKey)
        guard alreadySentCount == 0 || alreadySentCount == nil else {
            Self.logger.info("Already sent push-to-start for \(eventID) to \(token.prefix(8))... — skipping")
            return
        }

        // Mark as sent (TTL 8 hours)
        try? await context.application.redis.setex(sentKey, to: "1", expirationInSeconds: 60 * 60 * 8).get()

        let attributes = LiveSportAttributes(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            eventID: eventID
        )
        let contentState = ContentState(
            homeScore: Int(game.intHomeScore ?? "") ?? 0,
            awayScore: Int(game.intAwayScore ?? "") ?? 0,
            status: game.strStatus,
            progress: game.strProgress
        )

        do {
            let notification = APNSStartLiveActivityNotification(
                expiration: .immediately,
                priority: .immediately,
                appID: "com.KomodoLLC.SportsCal",
                contentState: contentState,
                timestamp: Int(Date().timeIntervalSince1970),
                attributes: attributes,
                attributesType: "LiveSportActivityAttributes",
                alert: APNSAlertNotificationContent(
                    title: .raw("\(homeTeam) vs \(awayTeam)"),
                    body: .raw("Game is starting now!")
                )
            )
            try await apnsClient.sendStartLiveActivityNotification(notification, deviceToken: token)
            Self.logger.info("Sent push-to-start for \(homeTeam) vs \(awayTeam) to token \(token.prefix(8))...")
        } catch {
            Self.logger.error("Failed to send push-to-start for event \(eventID): \(error)")
            // Clean up stale tokens so they don't keep failing
            if let apnsError = error as? APNSError,
               apnsError.reason == .badDeviceToken || apnsError.reason == .unregistered {
                Self.logger.warning("Removing stale push-to-start token \(token.prefix(8))...")
                let keyPrefix = isDebug ? "debug-PushToStart-" : "PushToStart-"
                let eventsKeyPrefix = isDebug ? "debug-PushToStartEvents-" : "PushToStartEvents-"
                _ = try? await context.application.redis.delete([RedisKey(keyPrefix + token)]).get()
                _ = try? await context.application.redis.delete([RedisKey(eventsKeyPrefix + token)]).get()
            }
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
        func translateEvents(_ events: [Game]) -> [Game] {
            events.map { game in
                let homeID = game.idHomeTeam.flatMap { mapping[$0] } ?? game.idHomeTeam
                let awayID = game.idAwayTeam.flatMap { mapping[$0] } ?? game.idAwayTeam
                guard homeID != game.idHomeTeam || awayID != game.idAwayTeam else { return game }
                return Game(idLiveScore: game.idLiveScore, idEvent: game.idEvent, strSport: nil, idLeague: game.idLeague, strLeague: nil, idHomeTeam: homeID, idAwayTeam: awayID, strHomeTeam: game.strHomeTeam, strAwayTeam: game.strAwayTeam, strHomeTeamBadge: game.strHomeTeamBadge, strAwayTeamBadge: game.strAwayTeamBadge, intHomeScore: game.intHomeScore, intAwayScore: game.intAwayScore, strStatus: game.strStatus, strProgress: game.strProgress, strTimestamp: game.strTimestamp, lastPlay: game.lastPlay, homeLinescores: game.homeLinescores, awayLinescores: game.awayLinescores, homeLeaders: game.homeLeaders, awayLeaders: game.awayLeaders, isCompleted: game.isCompleted, isoDate: game.isoDate, leaderboardEntries: game.leaderboardEntries, sessions: game.sessions, venueName: game.venueName, homeTeamColor: game.homeTeamColor, awayTeamColor: game.awayTeamColor, homeRecord: game.homeRecord, awayRecord: game.awayRecord, legDisplay: game.legDisplay, aggregateScore: game.aggregateScore, homeSeed: game.homeSeed, awaySeed: game.awaySeed, playoff: game.playoff)
            }
        }

        return LiveScore(
            nba: liveScore.nba.map { LiveEvent(events: translateEvents($0.events)) },
            mlb: liveScore.mlb.map { LiveEvent(events: translateEvents($0.events)) },
            soccer: liveScore.soccer.map { LiveEvent(events: translateEvents($0.events)) },
            nfl: liveScore.nfl.map { LiveEvent(events: translateEvents($0.events)) },
            nhl: liveScore.nhl.map { LiveEvent(events: translateEvents($0.events)) },
            golf: liveScore.golf.map { LiveEvent(events: translateEvents($0.events)) },
            tennis: liveScore.tennis.map { LiveEvent(events: translateEvents($0.events)) },
            racing: liveScore.racing.map { LiveEvent(events: translateEvents($0.events)) }
        )
    }
    
    // MARK: - Schedule Merge

    /// Merges ESPN live data into the TheSportsDB-sourced schedule, updating scores/statuses
    /// while preserving TheSportsDB identifiers and scheduled start times.
    private func mergeESPNIntoSchedule(schedule: LiveScore, espn: LiveScore) -> LiveScore {
        LiveScore(
            nba: mergeSportEvents(schedule: schedule.nba, espn: espn.nba),
            mlb: mergeSportEvents(schedule: schedule.mlb, espn: espn.mlb),
            soccer: mergeSportEvents(schedule: schedule.soccer, espn: espn.soccer),
            nfl: mergeSportEvents(schedule: schedule.nfl, espn: espn.nfl),
            nhl: mergeSportEvents(schedule: schedule.nhl, espn: espn.nhl),
            golf: mergeSportEvents(schedule: schedule.golf, espn: espn.golf),
            tennis: mergeSportEvents(schedule: schedule.tennis, espn: espn.tennis),
            racing: mergeSportEvents(schedule: schedule.racing, espn: espn.racing)
        )
    }

    /// Normalizes team names to handle abbreviation differences
    /// (e.g., "LA Clippers" → "los angeles clippers", "NY Knicks" → "new york knicks")
    private func normalizeTeamName(_ name: String) -> String {
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
    /// Matches by team IDs + day, falls back to team names + day, or event name for individual sports.
    private func mergeSportEvents(schedule: LiveEvent?, espn: LiveEvent?) -> LiveEvent? {
        guard let schedule else { return espn }
        guard let espn, !espn.events.isEmpty else { return schedule }

        // Build ESPN lookup dictionaries
        // Key: (lowercased homeTeamID, lowercased awayTeamID, dayString)
        var espnByTeamIDs: [String: Game] = [:]
        // Key: (lowercased homeTeamName, lowercased awayTeamName, dayString)
        var espnByTeamNames: [String: Game] = [:]
        // Key: (normalized homeTeamName, normalized awayTeamName, dayString)
        var espnByNormalizedNames: [String: Game] = [:]
        // Key: lowercased event/tournament name (for individual sports)
        var espnByEventName: [String: Game] = [:]

        for game in espn.events {
            let day = dayString(from: game)

            if let homeID = game.idHomeTeam, let awayID = game.idAwayTeam,
               !homeID.isEmpty, !awayID.isEmpty {
                let key = "\(homeID.lowercased())|\(awayID.lowercased())|\(day)"
                espnByTeamIDs[key] = game
            }

            let nameKey = "\(game.strHomeTeam.lowercased())|\(game.strAwayTeam.lowercased())|\(day)"
            espnByTeamNames[nameKey] = game

            let normalizedKey = "\(normalizeTeamName(game.strHomeTeam))|\(normalizeTeamName(game.strAwayTeam))|\(day)"
            espnByNormalizedNames[normalizedKey] = game

            if game.isIndividualSport {
                espnByEventName[game.strHomeTeam.lowercased()] = game
            }
        }

        var matchedESPNIDs = Set<String>()

        let merged = schedule.events.map { scheduleGame -> Game in
            let day = dayString(from: scheduleGame)
            var espnMatch: Game?

            // Primary: match by team IDs + day
            if let homeID = scheduleGame.idHomeTeam, let awayID = scheduleGame.idAwayTeam,
               !homeID.isEmpty, !awayID.isEmpty {
                let key = "\(homeID.lowercased())|\(awayID.lowercased())|\(day)"
                espnMatch = espnByTeamIDs[key]
            }

            // Fallback: match by team names + day
            if espnMatch == nil {
                let nameKey = "\(scheduleGame.strHomeTeam.lowercased())|\(scheduleGame.strAwayTeam.lowercased())|\(day)"
                espnMatch = espnByTeamNames[nameKey]
            }

            // Fallback: match by normalized team names + day (handles "LA" vs "Los Angeles" etc.)
            if espnMatch == nil {
                let normalizedKey = "\(normalizeTeamName(scheduleGame.strHomeTeam))|\(normalizeTeamName(scheduleGame.strAwayTeam))|\(day)"
                espnMatch = espnByNormalizedNames[normalizedKey]
            }

            // Individual sports: match by event/tournament name
            if espnMatch == nil && scheduleGame.isIndividualSport {
                espnMatch = espnByEventName[scheduleGame.strHomeTeam.lowercased()]
            }

            if let match = espnMatch {
                matchedESPNIDs.insert(match.id)
            }

            guard let espnGame = espnMatch else { return scheduleGame }

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
                homeInjuries: scheduleGame.homeInjuries ?? espnGame.homeInjuries,
                awayInjuries: scheduleGame.awayInjuries ?? espnGame.awayInjuries,
                raceTiming: scheduleGame.raceTiming ?? espnGame.raceTiming,
                playoff: espnGame.playoff ?? scheduleGame.playoff
            )
        }

        // Append ESPN-only games (no TheSportsDB match),
        // but skip games that already exist in the schedule by normalized team+day
        // (catches name mismatches like "LA Clippers" vs "Los Angeles Clippers")
        var scheduleByDay: Set<String> = []
        for game in schedule.events {
            let day = dayString(from: game)
            let home = normalizeTeamName(game.strHomeTeam)
            let away = normalizeTeamName(game.strAwayTeam)
            scheduleByDay.insert("\(home)|\(away)|\(day)")
            scheduleByDay.insert("\(away)|\(home)|\(day)")
        }

        let unmatchedESPN = espn.events.filter { game in
            guard !matchedESPNIDs.contains(game.id) else { return false }
            let day = dayString(from: game)
            let home = normalizeTeamName(game.strHomeTeam)
            let away = normalizeTeamName(game.strAwayTeam)
            let key = "\(home)|\(away)|\(day)"
            return !scheduleByDay.contains(key)
        }

        return LiveEvent(events: merged + unmatchedESPN)
    }

    /// Extracts a "YYYY-MM-DD" day string from a Game for same-day matching.
    private func dayString(from game: Game) -> String {
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
                return Game(idLiveScore: foundEvent.idLiveScore, idEvent: foundEvent.idEvent, strSport: nil, idLeague: foundEvent.idLeague, strLeague: nil, idHomeTeam: foundEvent.idHomeTeam, idAwayTeam: foundEvent.idAwayTeam, strHomeTeam: foundEvent.strHomeTeam, strAwayTeam: foundEvent.strAwayTeam, strHomeTeamBadge: foundEvent.strHomeTeamBadge, strAwayTeamBadge: foundEvent.strAwayTeamBadge, intHomeScore: event.intHomeScore, intAwayScore: event.intAwayScore, strStatus: event.strStatus, strProgress: event.strProgress, strTimestamp: foundEvent.strTimestamp, lastPlay: event.lastPlay, homeLinescores: event.homeLinescores, awayLinescores: event.awayLinescores, homeLeaders: event.homeLeaders, awayLeaders: event.awayLeaders, isCompleted: event.isCompleted, isoDate: Game.getDate(timestamp: foundEvent.strTimestamp), leaderboardEntries: event.leaderboardEntries, sessions: event.sessions, venueName: event.venueName, homeTeamColor: event.homeTeamColor, awayTeamColor: event.awayTeamColor, homeRecord: event.homeRecord, awayRecord: event.awayRecord, legDisplay: event.legDisplay, aggregateScore: event.aggregateScore, homeSeed: event.homeSeed, awaySeed: event.awaySeed, playoff: event.playoff)
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
