//
//  LiveFixtureIndex.swift
//  SportsCalModel
//
//  Finds the schedule copy of a game that is live, so lists that show live games in their
//  own section can leave them out below.
//

import Foundation

/// The live feed and the schedule describe the same game under different ids: live games
/// come from ESPN (`401898409`), schedule rows from TheSportsDB (`2548865`). Matching on
/// `Game.id` alone misses them, and the game is listed twice. This also matches on league,
/// both team names and a kickoff within three hours — the window the server's schedule
/// merge uses.
public struct LiveFixtureIndex: Sendable {
    private let ids: Set<String>
    private let kickoffs: [String: [Date]]

    private static let window: TimeInterval = 3 * 60 * 60

    public init(live: [Game]) {
        var ids = Set<String>()
        var kickoffs: [String: [Date]] = [:]
        for game in live {
            ids.insert(game.id)
            if let key = Self.key(game), let date = Self.kickoff(game) {
                kickoffs[key, default: []].append(date)
            }
        }
        self.ids = ids
        self.kickoffs = kickoffs
    }

    public var isEmpty: Bool { ids.isEmpty }

    /// Whether `game` is one of the live games, by id or by fixture.
    public func contains(_ game: Game) -> Bool {
        if ids.contains(game.id) { return true }
        guard let key = Self.key(game), let date = Self.kickoff(game),
              let candidates = kickoffs[key] else { return false }
        return candidates.contains { abs($0.timeIntervalSince(date)) <= Self.window }
    }

    private static func kickoff(_ game: Game) -> Date? {
        game.isoDate ?? game.strTimestamp.flatMap(DateParsers.parse)
    }

    private static func key(_ game: Game) -> String? {
        guard let league = game.idLeague, !league.isEmpty else { return nil }
        return "\(league)|\(game.strHomeTeam.lowercased())|\(game.strAwayTeam.lowercased())"
    }
}
