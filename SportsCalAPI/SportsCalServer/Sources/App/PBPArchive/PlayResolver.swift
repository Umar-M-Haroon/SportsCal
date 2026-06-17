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

        // Tier 1: Redis hot cache.
        if let cached = try await req.kv.getJSON(key.rawValue, as: CachedPlays.self) {
            return cached
        }

        // Tier 2: SQLite archive (finalized games).
        if let archive = req.application.pbpArchive,
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

        do {
            let summary = try await ESPNNetworking.getPlayByPlaySummary(
                req: req.client, sport: resolvedSport, league: resolvedLeague, eventId: resolvedESPNID
            )
            let plays = summary.plays ?? []
            guard !plays.isEmpty else { return nil }
            let payload = CachedPlays(
                eventID: eventID,
                lastPlayId: plays.last?.id ?? "",
                plays: plays,
                isFinal: false,
                fetchedAt: Date()
            )
            // Write under the client-facing key so subsequent requests hit cache.
            try? await req.application.redis.set(key, toJSON: payload)
            req.logger.info("PBP on-demand fetch succeeded for \(eventID) → ESPN \(resolvedESPNID) (\(plays.count) plays)")
            return payload
        } catch {
            req.logger.warning("PBP on-demand fetch failed for \(eventID): \(error)")
            return nil
        }
    }
}
