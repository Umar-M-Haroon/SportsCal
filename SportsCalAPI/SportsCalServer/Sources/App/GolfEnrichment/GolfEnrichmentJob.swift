//
//  GolfEnrichmentJob.swift
//  SportsCalServer
//
//  Created by Umar Haroon on 4/11/26.
//

import Foundation
import Queues
import SportsCalModel
import Logging

/// Adds tournament context to golf events from ESPN's web leaderboard: course par, hole
/// pars and yardage, purse, defending champion, rounds and the (projected) cut. Runs every
/// 30 minutes, for upcoming, live and just-finished events. Hole-by-hole scores and round
/// stats come from the scoreboard itself (`LiveEvent`).
struct GolfEnrichmentJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.golf-enrichment")

    func run(context: QueueContext) async throws {
        let isDebug = context.application.environment == .development
        let client = context.application.client
        let redis = context.application.redis

        // Check staleness (> 30 minutes)
        let lastUpdateKey = RedisEndpoint.ESPN.golfEnrichmentLastUpdate.getValue(isDebug: isDebug)
        if let lastUpdate = try? await redis.get(lastUpdateKey, asJSON: Date.self) {
            let minutesSince = Date().timeIntervalSince(lastUpdate) / 60
            if minutesSince < 25 {
                Self.logger.info("Golf enrichment still fresh, skipping", metadata: [
                    "minutesSinceUpdate": "\(String(format: "%.0f", minutesSince))"
                ])
                await JobHeartbeat.recordSuccess(.golfEnrichment, app: context.application, isDebug: isDebug)
                return
            }
        }

        // Get current schedule to find active golf events
        let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
        guard let schedule = try? await redis.get(scheduleKey, asJSON: LiveScore.self),
              let golfEvents = schedule.golf?.events, !golfEvents.isEmpty else {
            Self.logger.info("No golf events in schedule, skipping enrichment")
            await JobHeartbeat.recordSuccess(.golfEnrichment, app: context.application, isDebug: isDebug)
            return
        }

        // Only enrich events that are active or recently completed
        let activeEvents = golfEvents.filter { game in
            let isActive = game.strStatus == "in"
            let isRecent = game.strStatus == "post" && game.isCompleted == true
            let isUpcoming = game.strStatus == "pre"
            return isActive || isRecent || isUpcoming
        }

        guard !activeEvents.isEmpty else {
            Self.logger.info("No active golf events to enrich")
            try? await redis.set(lastUpdateKey, toJSON: Date())
            await JobHeartbeat.recordSuccess(.golfEnrichment, app: context.application, isDebug: isDebug)
            return
        }

        Self.logger.info("Enriching golf events", metadata: ["count": "\(activeEvents.count)"])

        // Tournament context per event ID, from ESPN's web leaderboard (the site summary
        // endpoint this job used to read answers 404 for golf, so it enriched nothing).
        // Applied to the schedule as it is at write time (re-read under the lock), not to
        // the copy read above, which is minutes old by then.
        var contextByEvent: [String: GolfCourseInfo] = [:]

        for game in activeEvents {
            guard let eventId = game.idEvent else { continue }
            let tour = game.golfTour ?? .pga
            do {
                let leaderboard = try await ESPNNetworking.getGolfLeaderboard(req: client, eventId: eventId, tour: tour)
                if let info = Self.courseInfo(from: leaderboard, eventID: eventId) {
                    contextByEvent[eventId] = info
                }
            } catch {
                Self.logger.warning("Failed to enrich golf event", metadata: [
                    "eventId": "\(eventId)",
                    "error": "\(error)"
                ])
            }
        }

        // Write enriched schedule back: re-read → apply → write under the shared lock.
        var enrichmentCount = 0
        if !contextByEvent.isEmpty {
            let outcome = try await ScheduleStore.update(
                app: context.application, isDebug: isDebug, logger: Self.logger, writer: "GolfEnrichmentJob"
            ) { current in
                guard var current, let events = current.golf?.events else { return nil }
                enrichmentCount = 0
                current.golf = LiveEvent(events: events.map { game in
                    guard let id = game.idEvent, let info = contextByEvent[id] else { return game }
                    enrichmentCount += 1
                    return Self.applying(info, to: game)
                })
                return current
            }
            // Retry next run rather than marking fresh when the lock was busy.
            guard outcome != .lockTimeout else { return }
        }

        try await redis.set(lastUpdateKey, toJSON: Date())

        Self.logger.info("Golf enrichment complete", metadata: [
            "enriched": "\(enrichmentCount)",
            "total": "\(activeEvents.count)"
        ])
        await JobHeartbeat.recordSuccess(.golfEnrichment, app: context.application, isDebug: isDebug)
    }

    // MARK: - Tournament context

    /// Course par, hole pars and yardage plus the tournament's purse, defending champion,
    /// rounds and (projected) cut.
    static func courseInfo(from response: ESPNNetworking.GolfLeaderboardResponse, eventID: String) -> GolfCourseInfo? {
        guard let event = response.events?.first(where: { $0.id == eventID }) ?? response.events?.first else { return nil }
        let course = event.courses?.first(where: { $0.host == true }) ?? event.courses?.first
        let holePars = course?.holes?.sorted(by: { $0.number < $1.number }).compactMap(\.shotsToPar)
        guard let par = course?.shotsToPar, GolfPar.plausiblePar.contains(par) else { return nil }
        let champion = event.defendingChampion?.athlete?.displayName
        return GolfCourseInfo(
            courseName: course?.name ?? "",
            par: par,
            holePars: holePars?.count == 18 ? holePars : nil,
            purse: event.displayPurse,
            defendingChampion: (champion?.isEmpty ?? true) ? nil : champion,
            numberOfRounds: event.tournament?.numberOfRounds,
            cutRound: event.tournament?.cutRound,
            cutScore: event.tournament?.cutScore,
            cutCount: event.tournament?.cutCount,
            yardage: course?.totalYards
        )
    }

    /// `game` with the leaderboard feed's course info. The scoreboard's own course name
    /// and hole pars win where it has them (they're per-event, the feed's are per-host).
    static func applying(_ info: GolfCourseInfo, to game: Game) -> Game {
        var enriched = game
        if let existing = game.golfCourseInfo {
            enriched.golfCourseInfo = GolfCourseInfo(
                courseName: existing.courseName, par: existing.par,
                holePars: existing.holePars ?? info.holePars
            ).withContext(from: info)
        } else {
            enriched.golfCourseInfo = info
        }
        return enriched
    }
}
