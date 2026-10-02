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

    static func resolve(app: Application, teamID: String, league: Leagues, isDebug: Bool) async -> TeamSeasonStats? {
        guard let espnTeamID = await espnTeamID(for: teamID, league: league, app: app, isDebug: isDebug) else {
            logger.debug("No ESPN team for TheSportsDB team", metadata: ["teamID": "\(teamID)", "league": "\(league)"])
            return nil
        }
        do {
            let current = try await ESPNNetworking.getCoreSeason(req: app.client, league: league)
            guard let year = current.year else { return nil }
            // Preseason (or a season a few days old) has no regular-season stats yet:
            // ESPN 404s, or ranks a handful of games. Fall back to last season's.
            if let espn = try? await ESPNNetworking.getCoreTeamStatistics(req: app.client, league: league, year: year, espnTeamID: espnTeamID),
               let stats = TeamSeasonStats(espn: espn, league: league, season: current.displayName ?? "\(year)", isPreviousSeason: false) {
                return stats
            }
            let previous = year - 1
            let espn = try await ESPNNetworking.getCoreTeamStatistics(req: app.client, league: league, year: previous, espnTeamID: espnTeamID)
            let label = (try? await ESPNNetworking.getCoreSeason(req: app.client, league: league, year: previous))?.displayName ?? "\(previous)"
            return TeamSeasonStats(espn: espn, league: league, season: label, isPreviousSeason: true)
        } catch {
            logger.debug("Team season stats fetch failed", metadata: ["teamID": "\(teamID)", "error": "\(error)"])
            return nil
        }
    }

    /// TheSportsDB → ESPN team ID, by inverting the `ESPN-ID-Map` that ESPNTeamFetchJob
    /// writes (`"{bucket}:{espnID}" → tsdbID`).
    static func espnTeamID(for teamID: String, league: Leagues, app: Application, isDebug: Bool) async -> String? {
        let mappingKey: RedisKey = isDebug ? "debug-ESPN-ID-Map" : "ESPN-ID-Map"
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
