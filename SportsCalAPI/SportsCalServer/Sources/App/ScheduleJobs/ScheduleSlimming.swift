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

import Foundation
import SportsCalModel

enum ScheduleSlimming {
    /// Rows kept on a finished golf tournament.
    static let finishedGolfRows = 5

    static func slimmed(_ schedule: LiveScore) -> LiveScore {
        guard let golf = schedule.golf else { return schedule }
        var result = schedule
        result.golf = LiveEvent(events: golf.events.map(slimmedGolf))
        return result
    }

    static func slimmedGolf(_ game: Game) -> Game {
        guard ScheduleCalendarVersion.state(of: game) == .final,
              let entries = game.leaderboardEntries,
              entries.count > finishedGolfRows || entries.contains(where: { $0.roundDetails != nil }) else {
            return game
        }
        let top = entries.prefix(finishedGolfRows).map { entry in
            LeaderboardEntry(name: entry.name, score: entry.score, position: entry.position, headshot: entry.headshot,
                             thruHole: entry.thruHole, rounds: entry.rounds, constructor: entry.constructor, gap: entry.gap,
                             isCut: entry.isCut, movement: entry.movement, flagURL: entry.flagURL, flagAlt: entry.flagAlt,
                             teeTime: entry.teeTime, roundDetails: nil, stockCar: entry.stockCar)
        }
        var slim = game
        slim.leaderboardEntries = Array(top)
        return slim
    }
}
