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
/// `Game.id` alone misses them, and the game is listed twice.
///
/// A schedule row is the live game's copy when the ids match, or else when league and
/// both team names match and the kickoff is within three hours — the window the server's
/// schedule merge uses. Each live game claims only its nearest such row, so the other
/// half of a doubleheader stays listed.
public struct LiveFixtureIndex: Sendable {
    private let claimed: Set<String>

    private static let window: TimeInterval = 3 * 60 * 60

    /// - Parameters:
    ///   - live: the games shown as live.
    ///   - schedule: the rows that may hold their copies — the list about to be filtered.
    public init(live: [Game], schedule: [Game]) {
        guard !live.isEmpty else { claimed = []; return }
        let liveIDs = Set(live.map(\.id))
        var claimed = Set(schedule.lazy.map(\.id).filter(liveIDs.contains))

        var rows: [String: [(id: String, kickoff: Date)]] = [:]
        for game in schedule where !claimed.contains(game.id) {
            if let key = Self.key(game), let kickoff = Self.kickoff(game) {
                rows[key, default: []].append((game.id, kickoff))
            }
        }
        for game in live where !claimed.contains(game.id) {
            guard let key = Self.key(game), let kickoff = Self.kickoff(game) else { continue }
            let nearest = rows[key]?
                .filter { !claimed.contains($0.id) }
                .map { (id: $0.id, gap: abs($0.kickoff.timeIntervalSince(kickoff))) }
                .filter { $0.gap <= Self.window }
                .min { $0.gap < $1.gap }
            if let nearest { claimed.insert(nearest.id) }
        }
        self.claimed = claimed
    }

    public var isEmpty: Bool { claimed.isEmpty }

    /// Whether `game` is the schedule copy of a live game.
    public func contains(_ game: Game) -> Bool {
        claimed.contains(game.id)
    }

    private static func kickoff(_ game: Game) -> Date? {
        game.isoDate ?? game.strTimestamp.flatMap(DateParsers.parse)
    }

    private static func key(_ game: Game) -> String? {
        guard let league = game.idLeague, !league.isEmpty else { return nil }
        return "\(league)|\(game.strHomeTeam.lowercased())|\(game.strAwayTeam.lowercased())"
    }
}
