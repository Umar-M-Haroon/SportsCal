//
//  ESPNTennisJob.swift
//
//  Created by Umar Haroon on 2/7/26.
//

import Foundation
import Queues
import RediStack
import SportsCalModel
import Logging

struct ESPNTennisJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.espn-tennis")

    func run(context: Queues.QueueContext) async throws {
        let isDebug = context.application.environment == .development
        let ttlKey = RedisEndpoint.ESPN.allTennisScoreboards.getValue(isDebug: isDebug)
        let latestKey = RedisEndpoint.ESPN.latestTennisScoreboards.getValue(isDebug: isDebug)

        var priorBoards: [Leagues: Scoreboard] = [:]
        if let cached = try? await context.application.redis.get(ttlKey, asJSON: [Leagues: Scoreboard].self) {
            priorBoards = cached
        } else if let cached = try? await context.application.redis.get(latestKey, asJSON: [Leagues: Scoreboard].self) {
            priorBoards = cached
        }

        let leaguesToFetch = await tennisLeaguesToFetch(redis: context.application.redis, isDebug: isDebug)
        guard !leaguesToFetch.isEmpty else {
            if !priorBoards.isEmpty {
                try await context.application.redis.setex(ttlKey, toJSON: priorBoards, expirationInSeconds: 60 * 15)
                try await context.application.redis.set(latestKey, toJSON: priorBoards)
            }
            return
        }

        Self.logger.info("Fetching tennis leagues", metadata: ["leagues": "\(leaguesToFetch)"])
        var espnInfo = await withTaskGroup(of: (Leagues, Scoreboard?).self) { group in
            var results: [Leagues: Scoreboard] = [:]
            for league in leaguesToFetch {
                group.addTask {
                    // Ask for specific days. Passing `dates: nil` would let
                    // `usesSingleYearSeason` widen this to the whole-season board
                    // (~18 MB for ATP, ~23 MB for WTA) — on a minutely job that is
                    // ~41 MB of fetch-and-decode per tick, for live scores that only
                    // ever need the current day. A day board is ~1.3 MB and still
                    // carries the in-progress tournament's full draw.
                    var merged: Scoreboard?
                    for day in Self.dayKeys() {
                        do {
                            let board = try await Integrator.getESPNScoreboard(for: league, context.application.client, dates: day)
                            if var existing = merged {
                                // Dedupe across the day pair — a tournament spans both.
                                var seen = Set(existing.events.map(\.id))
                                for event in board.events where seen.insert(event.id).inserted {
                                    existing.events.append(event)
                                }
                                merged = existing
                            } else {
                                merged = board
                            }
                        } catch {
                            Self.logger.debug("Failed to fetch tennis scoreboard", metadata: [
                                "league": "\(league)",
                                "day":    "\(day)",
                                "error":  "\(error)"
                            ])
                        }
                    }
                    return (league, merged)
                }
            }
            for await (league, board) in group {
                if let board { results[league] = board }
            }
            return results
        }
        espnInfo.merge(priorBoards) { new, _ in new }

        try await context.application.redis.setex(ttlKey, toJSON: espnInfo, expirationInSeconds: 60 * 15)
        try await context.application.redis.set(latestKey, toJSON: espnInfo)
    }

    /// The ESPN `yyyyMMdd` day keys to fetch for live tennis.
    ///
    /// ESPN keys its boards to US Eastern, so a single UTC "today" is wrong for a third of
    /// the day: between 00:00Z and ~05:00Z (evening ET) UTC has already rolled over and we
    /// would ask for ESPN's *tomorrow*, blanking live scores during exactly the US prime-time
    /// window a US Open night session runs in. Formatting in ET fixes the seam; we still send
    /// both days so a match running past ET midnight (or ESPN filing one a day either side)
    /// stays covered. `ESPNScheduleWindowJob` takes the same today+tomorrow approach.
    static func dayKeys(now: Date = Date()) -> [Int] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "America/New_York") ?? .init(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return [now, tomorrow].compactMap { Int(formatter.string(from: $0)) }
    }

    private func tennisLeaguesToFetch(redis: RedisClient, isDebug: Bool) async -> [Leagues] {
        guard let active = await Integrator.activeLeagues(redis: redis, isDebug: isDebug) else {
            return Leagues.allCases.filter { $0.isTennis }
        }
        return active.filter { $0.isTennis }
    }
}
