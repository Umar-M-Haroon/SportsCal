//
//  StandingsSnapshotJob.swift
//  SportsCalServer
//
//  Created by Umar Haroon on 2/16/26.
//

import Foundation
import Queues
import RediStack
import SportsCalModel
import Logging

/// Scheduled job that runs daily to snapshot standings for each major league.
/// Stores in Redis as "Standings-{leagueID}-{YYYY-MM-DD}" with 90-day TTL.
struct StandingsSnapshotJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.standings-snapshot")

    /// Leagues to snapshot standings for
    private static let snapshotLeagues: [Leagues] = [
        .nba, .nfl, .nhl, .mlb, // Major US sports
        .English_Premier_League, .La_Liga, .German_Bundesliga, .Serie_A, .Ligue_1, // Top 5 soccer
        .MLS,
        .FIFA_World_Cup // group-stage tables during the tournament
    ]

    func run(context: QueueContext) async throws {
        let isDebug = context.application.environment == .development
        let dateStr = Self.todayString()
        Self.logger.info("Starting daily standings snapshot for \(dateStr)")

        for league in Self.snapshotLeagues {
            do {
                let standingsResponse = try await ESPNNetworking.getStandings(
                    req: context.application.client,
                    DecodeType: StandingsResponse.self,
                    league: league
                )

                // Build a slim snapshot
                let snapshot = StandingsSnapshot(
                    date: dateStr,
                    leagueID: league.rawValue,
                    entries: Self.extractEntries(from: standingsResponse)
                )

                let key: RedisKey = isDebug
                    ? "debug-Standings-\(league.rawValue)-\(dateStr)"
                    : "Standings-\(league.rawValue)-\(dateStr)"

                let data = try JSONEncoder().encode(snapshot)
                let json = String(data: data, encoding: .utf8) ?? "{}"
                try await context.application.redis.setex(key, to: json, expirationInSeconds: 90 * 24 * 60 * 60).get()

                Self.logger.info("Saved standings snapshot for \(league.leagueName) on \(dateStr)")
            } catch {
                Self.logger.error("Failed to snapshot \(league.leagueName): \(error.localizedDescription)")
            }
        }
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    private static func extractEntries(from response: StandingsResponse) -> [StandingsSnapshotEntry] {
        var entries: [StandingsSnapshotEntry] = []
        guard let children = response.children else { return entries }

        for child in children {
            guard let standings = child.standings, let standingsEntries = standings.entries else { continue }
            for (index, entry) in standingsEntries.enumerated() {
                let wins = entry.stats?.first(where: { $0.name == "wins" })?.value.map { Int($0) }
                let losses = entry.stats?.first(where: { $0.name == "losses" })?.value.map { Int($0) }
                let points = entry.stats?.first(where: { $0.name == "points" })?.value.map { Int($0) }

                entries.append(StandingsSnapshotEntry(
                    teamID: entry.team?.id,
                    teamName: entry.team?.displayName ?? "Unknown",
                    teamAbbreviation: entry.team?.abbreviation,
                    teamColor: entry.team?.color,
                    teamLogo: entry.team?.logos?.first?.href,
                    position: index + 1,
                    division: child.name,
                    wins: wins ?? nil,
                    losses: losses ?? nil,
                    points: points ?? nil
                ))
            }
        }
        return entries
    }
}

// MARK: - Snapshot Models

struct StandingsSnapshot: Codable {
    let date: String
    let leagueID: Int
    let entries: [StandingsSnapshotEntry]
}

struct StandingsSnapshotEntry: Codable {
    let teamID: String?
    let teamName: String
    let teamAbbreviation: String?
    let teamColor: String?
    let teamLogo: String?
    let position: Int
    let division: String?
    let wins: Int?
    let losses: Int?
    let points: Int?
}
