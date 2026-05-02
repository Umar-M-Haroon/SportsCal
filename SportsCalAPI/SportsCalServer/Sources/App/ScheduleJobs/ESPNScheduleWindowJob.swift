//
//  ESPNScheduleWindowJob.swift
//
//  Maintains a "today + tomorrow" snapshot of ESPN scoreboards across every league with
//  an ESPN slug. Consumed by `Integrator.activeLeagues` to drive per-league fetch gating
//  — replacing the old cache-inspection heuristics that silently broke whenever a league's
//  scoreboard fell out of the live-fetch window.
//
//  Cadence: registered minutely but internally gated to one real run every ~15 min via
//  `espnScheduleWindowLastUpdate`. Burst is bounded at 6 concurrent fetches. On partial
//  failure the prior window is preserved — only successful league results get overwritten.
//

import Foundation
import Vapor
import Queues
import RediStack
import SportsCalModel
import Logging

struct ESPNScheduleWindowJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.espn-schedule-window")
    private static let refreshInterval: TimeInterval = 15 * 60
    private static let cacheTTL: Int = 30 * 60
    private static let maxConcurrent = 6

    func run(context: Queues.QueueContext) async throws {
        let isDebug = context.application.environment == .development
        let windowKey = RedisEndpoint.ESPN.espnScheduleWindow.getValue(isDebug: isDebug)
        let updateKey = RedisEndpoint.ESPN.espnScheduleWindowLastUpdate.getValue(isDebug: isDebug)

        if let lastUpdate = try? await context.application.redis.get(updateKey, asJSON: Date.self),
           Date().timeIntervalSince(lastUpdate) < Self.refreshInterval {
            return
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyyMMdd"
        dayFormatter.timeZone = .init(secondsFromGMT: 0)
        let todayInt = Int(dayFormatter.string(from: Date())) ?? 0
        let tomorrowInt: Int = {
            guard let tomorrow = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: Date()) else { return todayInt }
            return Int(dayFormatter.string(from: tomorrow)) ?? todayInt
        }()

        // Preserve prior snapshot so a partial fetch doesn't blow away good data.
        var merged: [Leagues: Scoreboard] = (try? await context.application.redis.get(
            windowKey, asJSON: [Leagues: Scoreboard].self
        )) ?? [:]

        let targets = Leagues.allCases.filter { $0.espnSlug != nil }
        Self.logger.info("Fetching ESPN schedule window", metadata: [
            "leagues":  "\(targets.count)",
            "today":    "\(todayInt)",
            "tomorrow": "\(tomorrowInt)"
        ])

        var fetched = 0
        var failed = 0
        var iterator = targets.makeIterator()

        await withTaskGroup(of: (Leagues, Scoreboard?).self) { group in
            func addNext() {
                guard let league = iterator.next() else { return }
                group.addTask {
                    let scoreboard = await Self.fetchMergedScoreboard(
                        league: league,
                        todayDates: todayInt,
                        tomorrowDates: tomorrowInt,
                        client: context.application.client
                    )
                    return (league, scoreboard)
                }
            }

            for _ in 0..<min(Self.maxConcurrent, targets.count) { addNext() }
            while let (league, result) = await group.next() {
                if let result {
                    merged[league] = result
                    fetched += 1
                } else {
                    failed += 1
                }
                addNext()
            }
        }

        try await context.application.redis.setex(windowKey, toJSON: merged, expirationInSeconds: Self.cacheTTL)
        try await context.application.redis.set(updateKey, toJSON: Date())

        let totalEvents = merged.values.map(\.events.count).reduce(0, +)
        Self.logger.info("ESPN schedule window refreshed", metadata: [
            "leagues":      "\(merged.count)",
            "fetched":      "\(fetched)",
            "failed":       "\(failed)",
            "totalEvents":  "\(totalEvents)"
        ])
    }

    /// Fetches today's and tomorrow's scoreboards for a league and merges them, de-duping
    /// by event ID. Returns nil only if BOTH calls fail — a single success still populates
    /// the window for this league.
    private static func fetchMergedScoreboard(
        league: Leagues,
        todayDates: Int,
        tomorrowDates: Int,
        client: some Client
    ) async -> Scoreboard? {
        async let todayResult = fetchScoreboard(league: league, dates: todayDates, client: client)
        async let tomorrowResult = fetchScoreboard(league: league, dates: tomorrowDates, client: client)
        let today = await todayResult
        let tomorrow = await tomorrowResult

        switch (today, tomorrow) {
        case (nil, nil):
            return nil
        case (let t?, nil):
            return t
        case (nil, let t?):
            return t
        case (var t?, let n?):
            var seen = Set(t.events.map(\.id))
            for event in n.events where !seen.contains(event.id) {
                t.events.append(event)
                seen.insert(event.id)
            }
            return t
        }
    }

    private static func fetchScoreboard(league: Leagues, dates: Int, client: some Client) async -> Scoreboard? {
        do {
            return try await Integrator.getESPNScoreboard(for: league, client, dates: dates)
        } catch {
            Self.logger.debug("ESPN schedule window fetch failed", metadata: [
                "league": "\(league)",
                "dates":  "\(dates)",
                "error":  "\(error)"
            ])
            return nil
        }
    }
}
