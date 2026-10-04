//
//  TeamSeasonStatsResolver.swift
//  SportsCalServer
//
//  Resolves a TheSportsDB team to its ESPN ID and fetches its season stats with league
//  ranks for the team page's rank card.
//

import Foundation
import Vapor
import Redis
import SportsCalModel

enum TeamSeasonStatsResolver {
    private static let logger = Logger(label: "com.sportscal.team-season-stats")

    /// Why a lookup came back empty.
    enum Outcome {
        case stats(TeamSeasonStats)
        /// ESPN has nothing for this team (unmapped, or no season with stats). Safe to
        /// cache for a while.
        case unavailable
        /// A transient failure. Not cached, so the next open retries.
        case failed
    }

    static func resolve(app: Application, teamID: String, league: Leagues, isDebug: Bool) async -> Outcome {
        guard let espnTeamID = await espnTeamID(for: teamID, league: league, app: app, isDebug: isDebug) else {
            logger.debug("No ESPN team for TheSportsDB team", metadata: ["teamID": "\(teamID)", "league": "\(league)"])
            return .unavailable
        }
        do {
            let current = try await currentSeason(league: league, app: app, isDebug: isDebug)
            guard let year = current.year else { return .unavailable }
            // Preseason has no regular-season stats yet and ESPN 404s; only then fall back
            // to last season. Any other failure is transient and must not be cached as
            // "last season" for hours mid-season.
            do {
                let espn = try await ESPNNetworking.getCoreTeamStatistics(req: app.client, league: league, year: year, espnTeamID: espnTeamID)
                if let stats = TeamSeasonStats(espn: espn, league: league, season: current.displayName ?? "\(year)", isPreviousSeason: false) {
                    return .stats(stats)
                }
            } catch NetworkError.badStatus(code: 404, _) {
                // fall through to last season
            }
            let previous = year - 1
            let espn = try await ESPNNetworking.getCoreTeamStatistics(req: app.client, league: league, year: previous, espnTeamID: espnTeamID)
            let label = (try? await ESPNNetworking.getCoreSeason(req: app.client, league: league, year: previous))?.displayName ?? "\(previous)"
            return TeamSeasonStats(espn: espn, league: league, season: label, isPreviousSeason: true).map(Outcome.stats) ?? .unavailable
        } catch NetworkError.badStatus(code: 404, _) {
            return .unavailable
        } catch {
            logger.debug("Team season stats fetch failed", metadata: ["teamID": "\(teamID)", "error": "\(error)"])
            return .failed
        }
    }

    /// The league's current season, cached for 12h: it's the same for every team page.
    private static func currentSeason(league: Leagues, app: Application, isDebug: Bool) async throws -> ESPNCoreSeason {
        let key: RedisKey = isDebug ? "debug-ESPN Core Season-\(league.rawValue)" : "ESPN Core Season-\(league.rawValue)"
        if let cached = try? await app.redis.get(key, asJSON: ESPNCoreSeason.self) { return cached }
        let season = try await ESPNNetworking.getCoreSeason(req: app.client, league: league)
        try? await app.redis.setex(key, toJSON: season, expirationInSeconds: 60 * 60 * 12).get()
        return season
    }

    /// TheSportsDB → ESPN team ID, by inverting the `ESPN-ID-Map` that ESPNTeamFetchJob
    /// writes (`"{bucket}:{espnID}" → tsdbID`).
    static func espnTeamID(for teamID: String, league: Leagues, app: Application, isDebug: Bool) async -> String? {
        // College teams have no TheSportsDB ID: their games, and so the team page, carry
        // ESPN's, namespaced ("ncaaf-57").
        if league == .ncaaf { return Leagues.collegeESPNTeamID(teamID) ?? teamID }
        let mappingKey = RedisEndpoint.ESPN.espnIDMap.getValue(isDebug: isDebug)
        guard let map = try? await app.redis.get(mappingKey, asJSON: [String: String].self) else { return nil }
        return espnTeamID(for: teamID, bucket: league.sportBucket, in: map)
    }

    static func espnTeamID(for teamID: String, bucket: String, in map: [String: String]) -> String? {
        let prefix = bucket + ":"
        // Several ESPN IDs can map to one team (ESPN re-keys teams); the lowest is the
        // long-standing one, and picking deterministically keeps the cache stable.
        return map
            .filter { $0.value == teamID && $0.key.hasPrefix(prefix) }
            .map { String($0.key.dropFirst(prefix.count)) }
            .min { (Int($0) ?? .max, $0) < (Int($1) ?? .max, $1) }
    }
}
