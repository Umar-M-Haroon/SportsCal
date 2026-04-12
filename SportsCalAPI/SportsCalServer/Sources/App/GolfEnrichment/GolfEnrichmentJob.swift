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

/// Fetches detailed golf tournament data (course info, hole-by-hole scores, round stats) from ESPN Summary API.
/// Runs every 30 minutes. Only fetches for active/in-progress golf events.
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
                return
            }
        }

        // Get current schedule to find active golf events
        let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
        guard var schedule = try? await redis.get(scheduleKey, asJSON: LiveScore.self),
              let golfEvents = schedule.golf?.events, !golfEvents.isEmpty else {
            Self.logger.info("No golf events in schedule, skipping enrichment")
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
            return
        }

        Self.logger.info("Enriching golf events", metadata: ["count": "\(activeEvents.count)"])

        var enrichedGames = golfEvents
        var enrichmentCount = 0

        for game in activeEvents {
            guard let eventId = game.idEvent else { continue }

            do {
                let summary = try await ESPNNetworking.getGolfSummary(req: client, eventId: eventId)

                // Extract course info
                let courseInfo = extractCourseInfo(from: summary)

                // Extract per-player round details
                let playerRoundDetails = extractPlayerRoundDetails(from: summary, courseInfo: courseInfo)

                // Merge enrichment into game
                if let idx = enrichedGames.firstIndex(where: { $0.idEvent == eventId }) {
                    enrichedGames[idx] = gameWithEnrichment(
                        enrichedGames[idx],
                        courseInfo: courseInfo,
                        playerRoundDetails: playerRoundDetails
                    )
                    enrichmentCount += 1
                }
            } catch {
                Self.logger.warning("Failed to enrich golf event", metadata: [
                    "eventId": "\(eventId)",
                    "error": "\(error)"
                ])
            }
        }

        // Write enriched schedule back
        if enrichmentCount > 0 {
            schedule.golf = LiveEvent(events: enrichedGames)
            try await redis.set(scheduleKey, toJSON: schedule)
        }

        try await redis.set(lastUpdateKey, toJSON: Date())

        Self.logger.info("Golf enrichment complete", metadata: [
            "enriched": "\(enrichmentCount)",
            "total": "\(activeEvents.count)"
        ])
    }

    // MARK: - Extraction Helpers

    private func extractCourseInfo(from summary: ESPNNetworking.GolfSummaryResponse) -> GolfCourseInfo? {
        guard let course = summary.courses?.first,
              let name = course.name,
              let par = course.par else { return nil }

        let holePars = course.holes?.sorted(by: { $0.number < $1.number }).map(\.par)
        return GolfCourseInfo(courseName: name, par: par, holePars: holePars)
    }

    private func extractPlayerRoundDetails(
        from summary: ESPNNetworking.GolfSummaryResponse,
        courseInfo: GolfCourseInfo?
    ) -> [String: [GolfRoundDetail]] {
        var result: [String: [GolfRoundDetail]] = [:]

        guard let rounds = summary.rounds else { return result }
        let holePars = courseInfo?.holePars

        for round in rounds {
            guard let roundNum = round.number else { continue }

            for competitor in round.competitors ?? [] {
                guard let athleteName = competitor.athlete?.displayName else { continue }

                // Hole-by-hole scores
                var holeScores: [GolfHoleScore]?
                if let linescores = competitor.linescores, !linescores.isEmpty {
                    holeScores = linescores.compactMap { ls -> GolfHoleScore? in
                        guard let holeNum = ls.period, holeNum >= 1, holeNum <= 18 else { return nil }
                        let holePar = holePars != nil && holeNum <= holePars!.count ? holePars![holeNum - 1] : 4
                        return GolfHoleScore(hole: holeNum, par: holePar, score: ls.value)
                    }
                }

                // Round stats
                var stats: GolfRoundStats?
                if let statCategories = competitor.statistics {
                    stats = extractRoundStats(from: statCategories, holeScores: holeScores)
                }

                // Total score for this round
                let totalScore = holeScores?.compactMap(\.score).reduce(0, +)

                let detail = GolfRoundDetail(
                    roundNumber: roundNum,
                    totalScore: totalScore,
                    stats: stats,
                    holeScores: holeScores
                )

                var existing = result[athleteName] ?? []
                existing.append(detail)
                result[athleteName] = existing
            }
        }

        return result
    }

    private func extractRoundStats(
        from categories: [ESPNNetworking.GolfSummaryStatCategory],
        holeScores: [GolfHoleScore]?
    ) -> GolfRoundStats {
        var fairways: String?
        var gir: String?
        var putts: Int?

        for category in categories {
            for stat in category.stats ?? [] {
                switch stat.name {
                case "fairwaysHit":
                    fairways = stat.displayValue
                case "greensInRegulation":
                    gir = stat.displayValue
                case "putts":
                    putts = stat.value.map { Int($0) }
                default:
                    break
                }
            }
        }

        // Count birdies/bogeys/eagles/pars from hole scores
        var birdies = 0, bogeys = 0, eagles = 0, pars = 0
        if let holes = holeScores {
            for hole in holes {
                guard let score = hole.score else { continue }
                let diff = score - hole.par
                switch diff {
                case ...(-2): eagles += 1
                case -1: birdies += 1
                case 0: pars += 1
                default: bogeys += 1
                }
            }
        }

        let hasHoleData = holeScores?.contains(where: { $0.score != nil }) ?? false
        return GolfRoundStats(
            fairways: fairways,
            greensInRegulation: gir,
            putts: putts,
            birdies: hasHoleData ? birdies : nil,
            bogeys: hasHoleData ? bogeys : nil,
            eagles: hasHoleData ? eagles : nil,
            pars: hasHoleData ? pars : nil
        )
    }

    // MARK: - Game Merging

    private func gameWithEnrichment(
        _ game: Game,
        courseInfo: GolfCourseInfo?,
        playerRoundDetails: [String: [GolfRoundDetail]]
    ) -> Game {
        // Enrich leaderboard entries with round details
        let enrichedEntries = game.leaderboardEntries?.map { entry -> LeaderboardEntry in
            let details = playerRoundDetails[entry.name]?.sorted(by: { $0.roundNumber < $1.roundNumber })
            guard let details, !details.isEmpty else { return entry }
            return LeaderboardEntry(
                name: entry.name, score: entry.score, position: entry.position,
                headshot: entry.headshot, thruHole: entry.thruHole, rounds: entry.rounds,
                constructor: entry.constructor, gap: entry.gap,
                isCut: entry.isCut, movement: entry.movement,
                flagURL: entry.flagURL, flagAlt: entry.flagAlt,
                teeTime: entry.teeTime, roundDetails: details
            )
        }

        return Game(
            idLiveScore: game.idLiveScore, idEvent: game.idEvent, strSport: game.strSport,
            idLeague: game.idLeague, strLeague: game.strLeague,
            idHomeTeam: game.idHomeTeam, idAwayTeam: game.idAwayTeam,
            strHomeTeam: game.strHomeTeam, strAwayTeam: game.strAwayTeam,
            strHomeTeamBadge: game.strHomeTeamBadge, strAwayTeamBadge: game.strAwayTeamBadge,
            intHomeScore: game.intHomeScore, intAwayScore: game.intAwayScore,
            strStatus: game.strStatus, strProgress: game.strProgress,
            strTimestamp: game.strTimestamp,
            lastPlay: game.lastPlay,
            homeLinescores: game.homeLinescores, awayLinescores: game.awayLinescores,
            homeLeaders: game.homeLeaders, awayLeaders: game.awayLeaders,
            isCompleted: game.isCompleted, isoDate: game.isoDate,
            leaderboardEntries: enrichedEntries ?? game.leaderboardEntries,
            sessions: game.sessions,
            venueName: game.venueName,
            homeTeamColor: game.homeTeamColor, awayTeamColor: game.awayTeamColor,
            homeRecord: game.homeRecord, awayRecord: game.awayRecord,
            circuitInfo: game.circuitInfo,
            golfCourseInfo: courseInfo ?? game.golfCourseInfo
        )
    }
}
