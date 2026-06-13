//
//  InjuriesEnrichmentJob.swift
//  SportsCalServer
//
//  Created by Umar Haroon on 4/19/26.
//

import Foundation
import Queues
import RediStack
import SportsCalModel
import Logging

/// Fetches injury reports from ESPN for NBA/NFL/NHL/MLB.
/// Runs hourly with a 4-hour staleness check. Team IDs are translated to
/// TheSportsDB IDs (matching the schedule) before being written.
struct InjuriesEnrichmentJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.injuries-enrichment")

    private static let leagues: [(sport: String, league: String)] = [
        ("basketball", "nba"),
        ("football", "nfl"),
        ("hockey", "nhl"),
        ("baseball", "mlb"),
    ]

    func run(context: QueueContext) async throws {
        let isDebug = context.application.environment == .development
        let client = context.application.client
        let redis = context.application.redis

        let lastUpdateKey = RedisEndpoint.ESPN.injuriesLastUpdate.getValue(isDebug: isDebug)
        if let lastUpdate = try? await redis.get(lastUpdateKey, asJSON: Date.self) {
            let hoursSince = Date().timeIntervalSince(lastUpdate) / 3600
            if hoursSince < 4 {
                Self.logger.info("Injuries still fresh, skipping", metadata: [
                    "hoursSinceUpdate": "\(String(format: "%.1f", hoursSince))"
                ])
                return
            }
        }

        Self.logger.info("Fetching ESPN injuries")

        // Keyed by normalized team name — ESPN team IDs collide across sports in
        // the flat ESPN-ID-Map so name matching is more reliable.
        let injuriesByTeamName = await withTaskGroup(
            of: [String: [InjuryReport]].self,
            returning: [String: [InjuryReport]].self
        ) { group in
            for (sport, league) in Self.leagues {
                group.addTask {
                    await InjuriesNetworking.getInjuries(client: client, sport: sport, league: league)
                }
            }
            return await group.reduce(into: [String: [InjuryReport]]()) { acc, partial in
                acc.merge(partial, uniquingKeysWith: { a, _ in a })
            }
        }

        let injuriesKey = RedisEndpoint.ESPN.injuries.getValue(isDebug: isDebug)
        try await redis.set(injuriesKey, toJSON: injuriesByTeamName)
        try await redis.set(lastUpdateKey, toJSON: Date())

        let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
        if var schedule = try? await redis.get(scheduleKey, asJSON: LiveScore.self) {
            Self.applyInjuries(to: &schedule, lookup: injuriesByTeamName)
            try await redis.set(scheduleKey, toJSON: schedule)
            Self.logger.info("Injuries applied to schedule")
        }

        Self.logger.info("Injuries enrichment complete", metadata: [
            "teams": "\(injuriesByTeamName.count)",
            "reports": "\(injuriesByTeamName.values.reduce(0) { $0 + $1.count })"
        ])
    }

    /// Attaches cached injuries to the team sports in a LiveScore. Callers can use
    /// this to re-hydrate injuries after the schedule is rebuilt by other jobs.
    static func applyInjuries(to schedule: inout LiveScore, lookup: [String: [InjuryReport]], now: Date = Date()) {
        attachInjuries(to: &schedule.nba, lookup: lookup, now: now)
        attachInjuries(to: &schedule.nfl, lookup: lookup, now: now)
        attachInjuries(to: &schedule.nhl, lookup: lookup, now: now)
        attachInjuries(to: &schedule.mlb, lookup: lookup, now: now)
    }

    /// Injuries are only meaningful for games a user might preview or watch: live,
    /// just-finished, or upcoming within two weeks. They're only ever displayed on
    /// the game-detail screen, never in lists. Attaching a team's full injury report
    /// (free-text comments + headshot URLs) to *every* event it plays — including
    /// thousands of completed past-season games and far-future fixtures — bloated the
    /// schedule payload to ~85MB (77% injuries) and pegged server CPU re-encoding it
    /// on every minutely job and API request. Gate to a window around `now` so the
    /// feed only carries injuries where they're actually shown.
    static func isInjuryRelevant(_ game: Game, now: Date) -> Bool {
        guard let date = game.isoDate else { return false }
        let recentlyFinished: TimeInterval = 12 * 3600        // keep just-ended games
        let upcomingHorizon: TimeInterval = 14 * 24 * 3600    // ~two weeks ahead
        return date >= now.addingTimeInterval(-recentlyFinished)
            && date <= now.addingTimeInterval(upcomingHorizon)
    }

    static func attachInjuries(to liveEvent: inout LiveEvent?, lookup: [String: [InjuryReport]], now: Date = Date()) {
        guard var event = liveEvent else { return }
        event.events = event.events.map { game in
            guard isInjuryRelevant(game, now: now) else {
                // Strip any injuries a prior (ungated) run left on now-irrelevant
                // games so the payload shrinks instead of carrying stale reports.
                guard game.homeInjuries != nil || game.awayInjuries != nil else { return game }
                return gameWithInjuries(game, home: nil, away: nil)
            }
            let home = lookup[InjuriesNetworking.normalize(game.strHomeTeam)]
            let away = lookup[InjuriesNetworking.normalize(game.strAwayTeam)]
            guard home != nil || away != nil else { return game }
            return gameWithInjuries(game, home: home, away: away)
        }
        liveEvent = event
    }

    static func gameWithInjuries(_ game: Game, home: [InjuryReport]?, away: [InjuryReport]?) -> Game {
        Game(
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
            leaderboardEntries: game.leaderboardEntries,
            sessions: game.sessions,
            venueName: game.venueName,
            homeTeamColor: game.homeTeamColor, awayTeamColor: game.awayTeamColor,
            homeRecord: game.homeRecord, awayRecord: game.awayRecord,
            circuitInfo: game.circuitInfo, golfCourseInfo: game.golfCourseInfo,
            legDisplay: game.legDisplay, aggregateScore: game.aggregateScore,
            homeSeed: game.homeSeed, awaySeed: game.awaySeed, tournamentName: game.tournamentName,
            homeInjuries: home, awayInjuries: away,
            raceTiming: game.raceTiming,
            playoff: game.playoff
        )
    }
}
