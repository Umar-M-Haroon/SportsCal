//
//  PlayResolver.swift
//  SportsCalServer
//
//  Shared play-by-play resolution used by both `GET /plays/:eventID` and the
//  developer `/replay/:eventID` WebSocket. Walks the same tiers the `/plays` route
//  has always used: Redis hot cache → SQLite archive (finalized games) → on-demand
//  ESPN summary fetch (resolving TSDB → ESPN via the enrichment map, or trusting a
//  caller-supplied sport/league when the eventID is already an ESPN ID).
//

import Vapor
import Redis
import SportsCalModel

enum PlayResolver {
    /// Resolves the play-by-play for an event, or `nil` if nothing is available.
    /// `sport`/`league` are ESPN slugs used only for the on-demand fetch fallback
    /// (ignored once a Redis/archive/map hit is found).
    static func resolve(
        req: Request,
        eventID: String,
        sport: String?,
        league: String?
    ) async throws -> CachedPlays? {
        let isDebug = req.application.environment == .development
        let key = RedisEndpoint.ESPN.playByPlay(eventID).getValue(isDebug: isDebug)

        // Tier 1: Redis hot cache. A college game the job doesn't keep fresh (it budgets
        // to featured games) is served for 90s, then refetched on the next request — one
        // ESPN fetch per game per 90s however many people are watching it.
        let collegeSlug = Leagues.ncaaf.espnSlug ?? "college-football"
        let hot = try await req.kv.getJSON(key.rawValue, as: CachedPlays.self)
        if let hot, !CollegePBPPolicy.isStale(hot, isCollege: league == collegeSlug) {
            return hot
        }

        // Tier 2: SQLite archive (finalized games). A stale college hit skips it: the game
        // isn't final, so it can't be in the archive.
        if hot == nil,
           let archive = req.application.pbpArchive,
           let archived = try? await archive.lookup(eventID: eventID) {
            return archived
        }

        // Tier 3: on-demand ESPN fetch. Resolve TSDB → ESPN via the enrichment map,
        // else fall back to a caller-supplied sport/league (eventID must already be ESPN).
        let mapKey = RedisEndpoint.ESPN.espnEventMap.getValue(isDebug: isDebug)
        let eventMap: [String: ESPNEventMapping] = (try? await req.kv.getJSON(
            mapKey.rawValue, as: [String: ESPNEventMapping].self
        )) ?? [:]

        let resolvedESPNID: String
        let resolvedSport: String
        let resolvedLeague: String
        if let mapping = eventMap[eventID] {
            resolvedESPNID = mapping.espnEventID
            resolvedSport = mapping.sport
            resolvedLeague = mapping.league
        } else if let sport, let league, !sport.isEmpty, !league.isEmpty {
            resolvedESPNID = eventID
            resolvedSport = sport
            resolvedLeague = league
        } else {
            return nil
        }

        // Single-flight: everyone asking for the same event while a fetch is in flight
        // shares it, so a popular game going stale costs one ESPN request, not one per
        // viewer. Runs against the application (not this request), since the shared task
        // can outlive the request that started it.
        let app = req.application
        let fetched = await OnDemandPlayFetches.shared.run(eventID: eventID) {
            await fetchOnDemand(
                app: app, key: key, eventID: eventID,
                espnID: resolvedESPNID, sport: resolvedSport, league: resolvedLeague
            )
        }
        // A stale copy beats a 404 while ESPN is unreachable or has nothing yet.
        return fetched ?? hot
    }

    /// Fetches a summary from ESPN and writes it under the client-facing key. Nil when
    /// ESPN fails or has neither plays nor extras.
    private static func fetchOnDemand(
        app: Application,
        key: RedisKey,
        eventID: String,
        espnID: String,
        sport: String,
        league: String
    ) async -> CachedPlays? {
        do {
            let summary = try await ESPNNetworking.getPlayByPlaySummary(
                req: app.client, sport: sport, league: league, eventId: espnID
            )
            let plays = summary.allPlays
            // Some summaries have no plays yet but do have win probability and a box
            // score, so an empty play list alone isn't a miss.
            let extras = summary.extras(league: Leagues(slug: league), isFinal: false)
            guard !plays.isEmpty || !extras.isEmpty else { return nil }
            let payload = CachedPlays(
                eventID: eventID,
                lastPlayId: plays.last?.id ?? "",
                plays: plays,
                isFinal: false,
                fetchedAt: Date(),
                winProbability: extras.winProbability,
                teamStats: extras.teamStats
            )
            // Write under the client-facing key so subsequent requests hit cache.
            try? await app.redis.set(key, toJSON: payload)
            app.logger.info("PBP on-demand fetch succeeded for \(eventID) → ESPN \(espnID) (\(plays.count) plays)")
            return payload
        } catch {
            app.logger.warning("PBP on-demand fetch failed for \(eventID): \(error)")
            return nil
        }
    }
}

/// In-flight on-demand play-by-play fetches, by event ID. Concurrent requests for one
/// event join the fetch already running instead of starting their own.
actor OnDemandPlayFetches {
    static let shared = OnDemandPlayFetches()
    private var inFlight: [String: Task<CachedPlays?, Never>] = [:]

    func run(eventID: String, fetch: @escaping @Sendable () async -> CachedPlays?) async -> CachedPlays? {
        if let running = inFlight[eventID] { return await running.value }
        let task = Task { await fetch() }
        inFlight[eventID] = task
        let result = await task.value
        inFlight[eventID] = nil
        return result
    }
}
