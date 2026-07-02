//
//  LiveTicker.swift
//
//  Adaptive fast-poll loop that gets in-progress live scores close to real time.
//  Runs alongside the minutely scheduled jobs: when soccer/World Cup games are
//  in progress it polls ONLY those leagues every ~15s (vs the 60s scheduled
//  pipeline), surgically overlays the fresh scores onto `latestLiveInfo` (served
//  verbatim over /ws), and refreshes `latestSoccerScoreboards` so the next slow
//  ESPNFetchJob tick inherits — never regresses — the fast data.
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

    /// Cadence while in-progress games exist. Far below the 60s scheduled pipeline,
    /// well within ESPN limits (typically 1-4 leagues live at once).
    static let fastInterval: TimeInterval = 15
    /// Cadence while nothing is in progress — the slow pipeline owns kickoff transitions.
    static let idleInterval: TimeInterval = 60
    /// Floor for cooldown/error backoff.
    static let minBackoff: TimeInterval = 30

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
        return result ?? idleInterval
    }

    private static func runUnderLock(_ app: Application, isDebug: Bool) async throws -> TimeInterval {
        let liveKey = RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug)
        guard let cached = try? await app.redis.get(liveKey, asJSON: LiveScore.self) else {
            return idleInterval
        }

        // Leagues with at least one in-progress game, across every sport bucket.
        let leagues = inProgressLeagues(in: cached)
        guard !leagues.isEmpty else { return idleInterval }

        // Route each league to its configured source (ESPN by default; FIFA/MLB/NHL/NBA via env).
        let resolver = LiveSourceResolver.fromEnvironment()
        var working = cached
        var changed = Set<String>()

        for group in resolver.groups(for: leagues) {
            if let espn = group.source as? ESPNLiveSource {
                // ESPN's fast-path role is soccer only; other sports stay on the 60s pipeline
                // unless an explicit override source is configured for them.
                let soccerLeagues = group.leagues.filter { $0.isSoccer }
                guard !soccerLeagues.isEmpty else { continue }
                // Fetch boards so we can also refresh the ESPN-shaped soccer cache the slow
                // pipeline reads (prevents the next slow tick regressing us).
                let boards = await espn.fetchBoards(leagues: soccerLeagues, app: app)
                guard !boards.isEmpty else { continue }
                let games = boards.compactMap { LiveEvent(events: $0.value, league: $0.key) }
                    .flatMap { $0.events }
                let r = LiveMerge.overlay(cached: working, sport: .soccer, fresh: games, strategy: espn.matchStrategy)
                working = r.liveScore
                changed.formUnion(r.changedEventIDs)
                await refreshSoccerScoreboards(boards: boards, app: app, isDebug: isDebug)
            } else {
                // Override source (FIFA / MLB / NHL / NBA / paid): overlay its sport's bucket.
                // A fetch failure degrades silently to the slow ESPN pipeline — this sport
                // just isn't sped up this tick.
                let source = group.source
                guard let games = try? await source.fetchLive(leagues: group.leagues, app: app),
                      !games.isEmpty else { continue }
                let r = LiveMerge.overlay(cached: working, sport: source.sport, fresh: games, strategy: source.matchStrategy)
                working = r.liveScore
                changed.formUnion(r.changedEventIDs)
            }
        }

        guard !changed.isEmpty else { return fastInterval }

        // latestLiveInfo is served verbatim over /ws — write the fresh snapshot.
        try await app.redis.set(liveKey, toJSON: working)
        // Mirror to the detailed key if present so /all-live-games stays in sync.
        let fullKey = RedisEndpoint.ESPN.latestFullLiveInfo.getValue(isDebug: isDebug)
        if let exists = try? await app.redis.exists(fullKey), exists > 0 {
            try? await app.redis.set(fullKey, toJSON: working)
        }

        logger.info("LiveTicker updated live info", metadata: [
            "changed": "\(changed.count)",
            "leagues": "\(leagues.count)"
        ])

        // Fast goal-push / Live-Activity pass — only when scores actually changed, so the
        // install-key scan is paid on real goals (rare), not every tick. APNSJob dedups
        // each send via atomic claim keys, so overlap with the minutely job can't double-send.
        await fastPush(app: app, isDebug: isDebug)

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
