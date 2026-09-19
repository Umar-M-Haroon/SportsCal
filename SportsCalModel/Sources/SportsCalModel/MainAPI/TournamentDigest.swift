//
//  TournamentDigest.swift
//  SportsCalModel
//
//  Collapses a tournament's tennis matches into one summary row. Space-constrained
//  surfaces (widgets) show "Wimbledon · 4 live" with its top matches instead of letting one
//  tournament's draw take every slot.
//

import Foundation

public enum TournamentDigest {
    /// Replaces each tournament's tennis matches in `games` with one summary `Game`,
    /// placed where that tournament's first match was. Matches for which `keepSeparate`
    /// is true (followed players) stay as their own rows. Everything else passes through
    /// in order.
    public static func collapsingTennisMatches(_ games: [Game], keepSeparate: (Game) -> Bool = { _ in false }) -> [Game] {
        var groups: [String: [Game]] = [:]
        // Output slots: either a pass-through game or a tournament placeholder.
        enum Slot { case game(Game), tournament(String) }
        var slots: [Slot] = []

        for game in games {
            guard game.isTennisMatch, let name = game.tournamentName, !name.isEmpty, !keepSeparate(game) else {
                slots.append(.game(game))
                continue
            }
            if groups[name] == nil { slots.append(.tournament(name)) }
            groups[name, default: []].append(game)
        }

        return slots.compactMap { slot in
            switch slot {
            case .game(let game):        return game
            case .tournament(let name):  return groups[name].flatMap { summary(name: name, matches: $0) }
            }
        }
    }

    /// One row standing in for `matches` (all from tournament `name`).
    static func summary(name: String, matches: [Game]) -> Game? {
        guard let first = matches.first else { return nil }
        let live = matches.filter(\.isTennisMatchLive)
        let featured = matches.sorted(by: featuredOrder).prefix(3)
        let entries = featured.enumerated().map { index, match in
            LeaderboardEntry(name: "\(lastName(match.strHomeTeam)) v \(lastName(match.strAwayTeam))",
                             score: scoreLine(match), position: index + 1)
        }
        let progress = live.isEmpty
            ? "\(matches.count) \(matches.count == 1 ? "match" : "matches")"
            : "\(live.count) live"
        let earliest = matches.min { $0.sortTimestamp < $1.sortTimestamp } ?? first
        return Game(
            strSport: SportType.tennis.rawValue,
            idLeague: first.idLeague,
            strLeague: first.strLeague,
            strHomeTeam: name,
            strAwayTeam: "",
            strStatus: live.isEmpty ? earliest.strStatus : "in",
            strProgress: progress,
            strTimestamp: earliest.strTimestamp,
            isCompleted: matches.allSatisfy { $0.isCompleted == true },
            isoDate: earliest.isoDate,
            leaderboardEntries: entries,
            tournamentName: name
        )
    }

    /// Live first, then later rounds, then soonest.
    private static func featuredOrder(_ lhs: Game, _ rhs: Game) -> Bool {
        if lhs.isTennisMatchLive != rhs.isTennisMatchLive { return lhs.isTennisMatchLive }
        if lhs.roundDepth != rhs.roundDepth { return lhs.roundDepth > rhs.roundDepth }
        return lhs.sortTimestamp < rhs.sortTimestamp
    }

    private static func lastName(_ name: String) -> String {
        // Doubles pairs ("A / B") and TBD slots read fine as-is.
        guard !name.contains("/"), let last = name.split(separator: " ").last else { return name }
        return String(last)
    }

    /// "6-4 3-2" once sets exist, otherwise the round's short label.
    private static func scoreLine(_ match: Game) -> String {
        if let home = match.homeLinescores, let away = match.awayLinescores, !home.isEmpty {
            return zip(home, away).map { "\(Int($0))-\(Int($1))" }.joined(separator: " ")
        }
        return match.shortRoundLabel ?? ""
    }
}

extension Game {
    var isTennisMatchLive: Bool { strStatus == "in" }

    /// ESPN ISO timestamps sort correctly as strings; missing ones sort last.
    var sortTimestamp: String { strTimestamp ?? "~" }

    /// Rough draw position for ordering: final > semifinal > quarterfinal > earlier.
    var roundDepth: Int {
        guard let round = round?.lowercased() else { return 0 }
        if isQualifyingRound { return -1 }
        if round.contains("semifinal") { return 5 }
        if round.contains("quarterfinal") { return 4 }
        if isLateRound { return 6 }
        if round.contains("16") || round.contains("4th") { return 3 }
        return 1
    }

    /// "F", "SF", "QF", "R16", "Q"…, for tight spaces.
    public var shortRoundLabel: String? {
        guard let round, !round.isEmpty else { return nil }
        let lower = round.lowercased()
        if isQualifyingRound { return "Q" }
        if lower.contains("semifinal") { return "SF" }
        if lower.contains("quarterfinal") { return "QF" }
        if isLateRound { return "F" }
        if lower.contains("round of 16") { return "R16" }
        if let number = round.split(separator: " ").last, Int(number) != nil { return "R\(number)" }
        return round
    }
}
