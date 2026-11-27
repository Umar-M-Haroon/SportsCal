//
//  FantasyJob.swift
//  SportsCalServer
//
//  Keeps the fantasy game log whole. Live games are logged by the play-by-play pass
//  (`ESPNFetchJob` → `FantasyService.ingest`); this job fills in the rest:
//  - ESPN rosters (positions, jerseys), daily.
//  - Backfill: every final game of the season not yet logged — the weeks before this
//    feature shipped, and any game the live pass missed (a restart over a final).
//    A few summaries per run, spaced out, so a cold start fills over a few hours
//    without leaning on ESPN.
//

import Foundation
import Logging
import Queues
import SportsCalModel
import Vapor

struct FantasyJob: AsyncScheduledJob {
    static let logger = Logger(label: "com.sportscal.fantasy-job")

    /// Summaries per run; at a run every 15 minutes a full season backfills in ~3 hours.
    static let backfillPerRun = 16
    static let rosterMaxAge: TimeInterval = 24 * 60 * 60

    func run(context: QueueContext) async throws {
        let app = context.application
        let isDebug = app.environment == .development
        _ = try await JobLock.withLock(
            app.kv, name: "fantasy", ttl: 600, instanceID: app.instanceID, logger: Self.logger,
            body: { await Self.runUnderLock(app: app, isDebug: isDebug) }
        )
    }

    static func runUnderLock(app: Application, isDebug: Bool) async {
        for sport in SportType.allCases where FantasyScoring.supports(sport) {
            let rosters = await FantasyRosters.shared.current(app: app, sport: sport, isDebug: isDebug)
            if Date().timeIntervalSince(rosters.updated) > rosterMaxAge {
                do {
                    let set = try await FantasyRosters.refresh(app: app, sport: sport, isDebug: isDebug)
                    logger.info("Fantasy rosters refreshed", metadata: ["sport": "\(sport.rawValue)", "athletes": "\(set.athletes.count)"])
                } catch {
                    logger.warning("Fantasy roster refresh failed", metadata: ["error": "\(error)"])
                }
            }
            await backfill(sport: sport, app: app, isDebug: isDebug)
        }
    }

    /// Logs up to `backfillPerRun` final games of the current season that aren't logged yet,
    /// most recent weeks first (they matter most for this week's averages).
    static func backfill(sport: SportType, app: Application, isDebug: Bool) async {
        guard let archive = app.fantasyArchive, let path = FantasyService.espnPath(for: sport) else { return }
        do {
            let current = try await FantasyScoreboard.week(sport: sport, week: nil, seasonType: nil, app: app, isDebug: isDebug)
            // Preseason doesn't count; in the postseason, the whole regular season still does.
            guard current.seasonType >= 2, let currentWeek = current.week else { return }
            var weeks: [(type: Int, week: Int)] = []
            if current.seasonType == 3 {
                weeks += (1...currentWeek).reversed().map { (3, $0) }
                weeks += (1...18).reversed().map { (2, $0) }
            } else {
                weeks += (1...currentWeek).reversed().map { (2, $0) }
            }

            var budget = backfillPerRun
            for (type, week) in weeks where budget > 0 {
                let logged = try await archive.finalEventIDs(league: path.league, season: current.season, seasonType: type)
                let board = try await FantasyScoreboard.week(sport: sport, week: week, seasonType: type, app: app, isDebug: isDebug)
                guard board.season == current.season else { continue }
                for game in board.games where game.state == "post" && !logged.contains(game.id) && budget > 0 {
                    budget -= 1
                    do {
                        let summary = try await ESPNNetworking.getPlayByPlaySummary(
                            req: app.client, sport: path.sport, league: path.league, eventId: game.id
                        )
                        await FantasyService.ingest(summary: summary, sport: sport, espnEventID: game.id,
                                                    tsdbEventID: nil, app: app, isDebug: isDebug)
                    } catch {
                        logger.debug("Fantasy backfill fetch failed", metadata: ["eventID": "\(game.id)", "error": "\(error)"])
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
            if budget < backfillPerRun {
                logger.info("Fantasy backfill", metadata: ["sport": "\(sport.rawValue)", "games": "\(backfillPerRun - budget)"])
            }
        } catch {
            logger.warning("Fantasy backfill failed", metadata: ["error": "\(error)"])
        }
    }
}
