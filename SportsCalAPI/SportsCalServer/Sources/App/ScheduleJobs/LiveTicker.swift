//
//  LiveTicker.swift
//
//  Adaptive fast-poll loop that gets in-progress live scores close to real time.
//  Runs alongside the minutely scheduled jobs: while games are in progress it polls
//  ONLY the live leagues every ~5s (vs the 60s scheduled pipeline) from every source
//  configured for them, surgically overlays the furthest-along copy of each game onto
//  `latestLiveInfo` (served verbatim over /ws), and refreshes `latestSoccerScoreboards`
//  so the next slow ESPNFetchJob tick inherits — never regresses — the fast data.
//  Which source got each score change first is tallied in LiveSourceStats.
//
//  Leader-elected via JobLock so exactly one replica fast-polls. Backs off
//  automatically when the ESPN circuit breaker is tripped.
//

import Foundation
import Vapor
import SportsCalModel
import Logging

/// Stores the running ticker Task so the lifecycle handler can cancel it on shutdown.
struct LiveTickerTaskKey: StorageKey {
    typealias Value = Task<Void, Never>
}

/// Starts the LiveTicker loop after boot (so Redis/clients are ready — starting it
/// inline in configure() races the boot sequence and trips "No redis found") and
/// cancels it on shutdown (prevents a leaked loop in dev/tests where the process is reused).
struct LiveTickerLifecycle: LifecycleHandler {
    func didBootAsync(_ application: Application) async throws {
        guard application.environment != .testing else { return }
        application.storage[LiveTickerTaskKey.self] = LiveTicker.start(application)
    }

    func shutdown(_ application: Application) {
        application.storage[LiveTickerTaskKey.self]?.cancel()
    }
}

enum LiveTicker {
    private static let logger = Logger(label: "com.sportscal.live-ticker")

    /// Cadence while in-progress games exist. ESPN's scoreboards are CDN-cached for 1-10s
    /// (measured Oct 2026: NFL 7, NBA 10, NHL 8, MLB 3, soccer 3-4, college 1), so 5s picks
    /// up most changes within one cache lifetime. One request per live league per tick —
    /// the heavy ones are paced separately (`Paced`).
    static let fastInterval: TimeInterval = 5
    /// Cadence while nothing is in progress — the slow pipeline owns kickoff transitions.
    static let idleInterval: TimeInterval = 60
    /// Floor for cooldown/error backoff.
    static let minBackoff: TimeInterval = 30

    /// Work that is too heavy for every 5s tick, and the most often it runs.
    enum Paced: Hashable {
        /// A league's board. College football's FBS board is ~1 MB on a Saturday.
        case board(Leagues)
        /// NASCAR / IndyCar / IMSA / WEC weekend rebuilds.
        case motorsport
        /// The fast push pass for sports without score alerts (basketball, baseball): a
        /// basket every few seconds would otherwise run the install scan on every tick.
        case quietPush

        var minRefresh: TimeInterval {
            switch self {
            case .board(.ncaaf): return 15
            case .board: return 0
            case .motorsport: return 15
            case .quietPush: return 15
            }
        }
    }

    /// When each paced item last ran. In-process: the ticker is leader-elected, and a
    /// failover just runs everything once on the new leader.
    actor Pacing {
        private var lastRun: [Paced: Date] = [:]

        /// Whether `item` may run now; marks it as run when it may.
        func take(_ item: Paced, now: Date = Date()) -> Bool {
            // Half a second of slack so a 15s item isn't pushed to the fourth 5s tick by jitter.
            if let last = lastRun[item], now.timeIntervalSince(last) < item.minRefresh - 0.5 { return false }
            lastRun[item] = now
            return true
        }
    }

    static let pacing = Pacing()

    /// Starts the loop and returns its handle. Caller stores it for shutdown cancel.
    static func start(_ app: Application) -> Task<Void, Never> {
        Task { await loop(app) }
    }

    private static func loop(_ app: Application) async {
        logger.info("LiveTicker started")
        while !Task.isCancelled {
            var sleepFor = fastInterval
            do {
                sleepFor = try await tickOnce(app)
            } catch {
                logger.error("LiveTicker tick failed", metadata: ["error": "\(error)"])
                sleepFor = minBackoff
            }
            // ±10% jitter so the 1-4 league fetches don't lockstep with each other
            // or with the minutely jobs (thundering-herd avoidance).
            let jitter = Double.random(in: -0.1...0.1) * sleepFor
            let nanos = UInt64(max(1, sleepFor + jitter) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanos)
            } catch {
                break // cancelled
            }
        }
        logger.info("LiveTicker stopped")
    }

    /// One iteration. Returns seconds to sleep before the next tick.
    @discardableResult
    static func tickOnce(_ app: Application) async throws -> TimeInterval {
        // Proactive backoff: don't even take the lock if ESPN is rate-limiting us.
        if let remaining = ESPNNetworking.globalCooldownRemaining {
            return max(minBackoff, remaining)
        }
        let isDebug = app.environment == .development
        let result = try await JobLock.withLock(
            app.kv,
            name: "live-ticker",
            ttl: 12,
            instanceID: app.instanceID,
            logger: logger,
            body: { try await runUnderLock(app, isDebug: isDebug) }
        )
        // nil = another replica holds the lock; back off to idle rather than spin.
        guard let result else { return idleInterval }
        await JobHeartbeat.recordSuccess(.liveTicker, app: app, isDebug: isDebug)
        return result
    }

    private static func runUnderLock(_ app: Application, isDebug: Bool) async throws -> TimeInterval {
        let liveKey = RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug)
        guard let cached = try? await app.redis.get(liveKey, asJSON: LiveScore.self) else {
            return idleInterval
        }

        // Leagues with at least one in-progress game, across every sport bucket.
        let leagues = inProgressLeagues(in: cached)
        guard !leagues.isEmpty else { return idleInterval }

        // Every source configured for a league races for it (ESPN for all of them; FIFA /
        // MLB / NHL / NBA / paid ones via env). Fetch everything FIRST, then apply the
        // overlays to a snapshot re-read just before the write: ESPNFetchJob may have
        // published a full rebuild (new games, other sports' scores) while these fetches
        // were in flight, and overlaying onto the pre-fetch copy would roll that back.
        let resolver = LiveSourceResolver.fromEnvironment()
        var overlays: [(sport: SportType, games: [Game], strategy: LiveMerge.MatchStrategy, source: String)] = []

        for group in resolver.groups(for: leagues) {
            if let espn = group.source as? ESPNLiveSource {
                var due = Set<Leagues>()
                for league in group.leagues where await pacing.take(.board(league)) { due.insert(league) }
                guard !due.isEmpty else { continue }
                let boards = await espn.fetchBoards(leagues: due, app: app)
                guard !boards.isEmpty else { continue }
                // One overlay per snapshot bucket: college football rides in the NFL bucket,
                // WNBA and the NCAA tournament in the basketball one.
                var byBucket: [SportType: [Game]] = [:]
                for (league, board) in boards {
                    guard let bucket = league.liveBucket,
                          let events = LiveEvent(events: board, league: league)?.events else { continue }
                    byBucket[bucket, default: []] += events
                }
                for (bucket, games) in byBucket {
                    overlays.append((bucket, games, espn.matchStrategy, espn.name))
                }
                // Refresh the ESPN-shaped soccer cache the slow pipeline reads, so its next
                // tick inherits rather than regresses the fast data.
                let soccerBoards = boards.filter { $0.key.isSoccer }
                if !soccerBoards.isEmpty {
                    await refreshSoccerScoreboards(boards: soccerBoards, app: app, isDebug: isDebug)
                }
            } else {
                // Extra source (FIFA / MLB / NHL / NBA / paid). A fetch failure just leaves the
                // league to ESPN this tick.
                let source = group.source
                guard let games = try? await source.fetchLive(leagues: group.leagues, app: app),
                      !games.isEmpty else { continue }
                overlays.append((source.sport, games, source.matchStrategy, source.name))
            }
        }
        // NASCAR owns its games outright (built from NASCAR's feed on both paths), so a
        // live weekend is rebuilt whole rather than overlaid: laps, flags and the running
        // order all live in its sessions, which the overlay doesn't carry.
        var nascar: [Game] = []
        if leagues.contains(where: \.isRacing), await pacing.take(.motorsport) {
            if leagues.contains(.nascarCup) {
                nascar += await NASCARService.liveGames(app: app, isDebug: isDebug)
            }
            if leagues.contains(.indycar) {
                nascar += await IndyCarService.liveGames(app: app, isDebug: isDebug)
            }
            // IMSA/WEC results are re-read at most every five minutes (their cache), so the
            // fast tick costs a Redis read until a new hour's classification is out.
            for series in AlKamelSeries.allCases where leagues.contains(series.league) {
                nascar += await AlKamelService.liveGames(series, app: app, isDebug: isDebug)
            }
        }

        guard !overlays.isEmpty || !nascar.isEmpty else { return fastInterval }

        let forcedSources = (try? await app.kv.getJSON(
            LiveSourceStats.forcedSourcesKey(isDebug: isDebug), as: [String: String].self
        )) ?? [:]
        let statsKey = LiveSourceStats.key(isDebug: isDebug)
        let now = Date()
        var stats = (try? await app.kv.getJSON(statsKey, as: LiveSourceStats.self)) ?? LiveSourceStats(since: now)

        var working = (try? await app.redis.get(liveKey, asJSON: LiveScore.self)) ?? cached
        var changed = Set<String>()
        var situationChanged = Set<String>()
        if !nascar.isEmpty {
            let before = Dictionary((working.racing?.events ?? []).compactMap { g in g.idEvent.map { ($0, g) } }, uniquingKeysWith: { a, _ in a })
            for game in nascar {
                guard let id = game.idEvent, before[id] != game else { continue }
                // Only a status change is worth the push scan; laps and positions just republish.
                if before[id]?.strStatus != game.strStatus { changed.insert(id) } else { situationChanged.insert(id) }
            }
            working.racing = ESPNFetchJob.replacingGames(in: working.racing, with: nascar)
        }
        for overlay in overlays {
            let r = LiveMerge.overlay(
                cached: working, sport: overlay.sport, fresh: overlay.games, strategy: overlay.strategy,
                race: LiveMerge.RaceOptions(source: overlay.source, forcedSources: forcedSources)
            )
            working = r.liveScore
            changed.formUnion(r.changedEventIDs)
            situationChanged.formUnion(r.situationChangedEventIDs)
            stats.record(source: overlay.source, observed: r.observedScores, behindCount: r.behindEventIDs.count, now: now)
        }
        // Small blob (bounded recent list, pruned sightings); a day's TTL so it resets on
        // its own once nothing is live.
        try? await app.kv.setJSON(statsKey, value: stats, ttl: 24 * 3600)

        guard !changed.isEmpty || !situationChanged.isEmpty else { return fastInterval }

        // latestLiveInfo is served verbatim over /ws — write the fresh snapshot.
        try await app.redis.set(liveKey, toJSON: working)
        // Mirror to the detailed key if present so /all-live-games stays in sync.
        let fullKey = RedisEndpoint.ESPN.latestFullLiveInfo.getValue(isDebug: isDebug)
        if let exists = try? await app.redis.exists(fullKey), exists > 0 {
            try? await app.redis.set(fullKey, toJSON: working)
        }

        logger.info("LiveTicker updated live info", metadata: [
            "changed": "\(changed.count)",
            "situationOnly": "\(situationChanged.count)",
            "leagues": "\(leagues.count)"
        ])

        // A count or runner change alone republishes the snapshot (above) but skips the
        // push scan; the minutely APNSJob carries it to Live Activities.
        guard !changed.isEmpty else { return fastInterval }

        // Fast goal-push / Live-Activity pass — only when scores actually changed, so the
        // install-key scan is paid on real goals, not every tick. A goal, touchdown or
        // hockey goal (an alerting sport) pushes at once; basketball and baseball scores,
        // which move constantly, push at most every 15s. APNSJob dedups each send via
        // atomic claim keys, so overlap with the minutely job can't double-send.
        let alerting = working.allGamesBySport.contains { sport, games in
            sport.alertsOnScoreChange && games.contains { $0.idEvent.map(changed.contains) ?? false }
        }
        if alerting {
            await fastPush(app: app, isDebug: isDebug)
        } else if await pacing.take(.quietPush) {
            await fastPush(app: app, isDebug: isDebug)
        }

        return fastInterval
    }

    /// Leagues with at least one in-progress (`strStatus == "in"`) game, across all buckets.
    private static func inProgressLeagues(in score: LiveScore) -> Set<Leagues> {
        let buckets = [score.nba, score.mlb, score.soccer, score.nfl, score.nhl, score.golf, score.tennis, score.racing]
        let games = buckets.compactMap { $0 }.flatMap { $0.events }
        return Set(
            games
                .filter { $0.strStatus == "in" }
                .compactMap { game -> Leagues? in
                    guard let raw = game.idLeague, let id = Int(raw) else { return nil }
                    return Leagues(rawValue: id)
                }
        )
    }

    /// Merge the fast-fetched boards into the cached `latestSoccerScoreboards` map. For the
    /// World Cup, merge today's events into the cached season board (preserving the full
    /// fixture list) rather than replacing it; other leagues store the imminent-window board,
    /// matching ESPNSoccerJob's own write.
    private static func refreshSoccerScoreboards(
        boards fresh: [Leagues: Scoreboard],
        app: Application,
        isDebug: Bool
    ) async {
        let ttlKey = RedisEndpoint.ESPN.allSoccerScoreboards.getValue(isDebug: isDebug)
        let latestKey = RedisEndpoint.ESPN.latestSoccerScoreboards.getValue(isDebug: isDebug)
        var boards = (try? await app.redis.get(latestKey, asJSON: [Leagues: Scoreboard].self)) ?? [:]
        for (league, board) in fresh {
            if league == .FIFA_World_Cup, var prior = boards[league] {
                prior.events = ESPNSoccerJob.mergeWorldCupEvents(season: prior.events, today: board.events)
                boards[league] = prior
            } else {
                boards[league] = board
            }
        }
        try? await app.redis.setex(ttlKey, toJSON: boards, expirationInSeconds: 60 * 15)
        try? await app.redis.set(latestKey, toJSON: boards)
    }

    private static func fastPush(app: Application, isDebug: Bool) async {
        guard app.storage[APNSConfiguredKey.self] == true else { return }
        do {
            try await APNSJob.runOnce(
                kv: app.kv,
                apns: app.apnsSending,
                clock: app.appClock,
                isDebug: isDebug,
                logger: logger,
                metrics: app.pushMetrics,
                telemetry: app.telemetry
            )
        } catch {
            logger.error("LiveTicker fast push failed", metadata: ["error": "\(error)"])
        }
    }
}
