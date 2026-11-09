//
//  ScheduleSlimming.swift
//
//  Detail the schedule doesn't need to carry for every game, cut before each write.
//
//  Finished golf tournaments were 4MB of the 28MB `/schedules` payload (prod,
//  2026-10-04): each kept its full leaderboard with hole-by-hole scorecards (~97KB),
//  for 179 tournaments nobody was looking at. Lists only show the winner and the top
//  few, so the schedule keeps the top five without scorecards; the tournament page
//  fetches the full leaderboard from `/golf/tournament/:league/:id`. Tournaments in
//  progress keep everything (they're on screen, and the live board replaces them).
//
//  Same idea for `ScoreboardExtras`: a soccer match's goal/card timeline and a baseball
//  game's pitchers are worth carrying for a few days after full time (result rows,
//  "who scored"), not for a season's worth of results. Past that the game keeps only
//  the small facts — winner, shootout score, R/H/E, TV.
//

import Foundation
import SportsCalModel

enum ScheduleSlimming {
    /// Rows kept on a finished golf tournament.
    static let finishedGolfRows = 5

    /// How long after its start a finished game keeps its heavy scoreboard detail.
    static let heavyDetailWindow: TimeInterval = 3 * 24 * 3600

    static func slimmed(_ schedule: LiveScore, now: Date = Date()) -> LiveScore {
        var result = schedule
        if let golf = schedule.golf {
            result.golf = LiveEvent(events: golf.events.map(slimmedGolf))
        }
        result.soccer = slimmedExtras(schedule.soccer, now: now)
        result.mlb = slimmedExtras(schedule.mlb, now: now)
        return result
    }

    /// Only soccer and baseball carry heavy extras (see `ScoreboardExtras.withoutHeavyDetail`).
    private static func slimmedExtras(_ event: LiveEvent?, now: Date) -> LiveEvent? {
        guard let event else { return nil }
        let cutoff = now.addingTimeInterval(-heavyDetailWindow)
        guard event.events.contains(where: { hasStaleHeavyDetail($0, cutoff: cutoff) }) else { return event }
        return LiveEvent(events: event.events.map { game in
            guard hasStaleHeavyDetail(game, cutoff: cutoff) else { return game }
            var slim = game
            slim.scoreboardExtras = game.scoreboardExtras?.withoutHeavyDetail
            return slim
        })
    }

    private static func hasStaleHeavyDetail(_ game: Game, cutoff: Date) -> Bool {
        guard let extras = game.scoreboardExtras, extras != extras.withoutHeavyDetail,
              let start = game.isoDate, start < cutoff else { return false }
        return ScheduleCalendarVersion.state(of: game) == .final
    }

    static func slimmedGolf(_ game: Game) -> Game {
        guard ScheduleCalendarVersion.state(of: game) == .final,
              let entries = game.leaderboardEntries,
              entries.count > finishedGolfRows
                || entries.contains(where: { $0.roundDetails?.contains(where: { $0.holeScores != nil }) ?? false }) else {
            return game
        }
        // The top five keep their per-round stats (birdies, bogeys, FIR/GIR, putts: a few
        // numbers a round); only the hole-by-hole scorecards go.
        let top = entries.prefix(finishedGolfRows).map { entry in
            var slim = entry
            slim.roundDetails = entry.roundDetails?.map { detail in
                var round = detail
                round.holeScores = nil
                return round
            }
            return slim
        }
        var slim = game
        slim.leaderboardEntries = Array(top)
        return slim
    }
}
