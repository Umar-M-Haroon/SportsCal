//
//  TeamSeasonSchedule.swift
//  SportsCalModel
//
//  A team's games grouped season → phase, in date order, with the game the team page
//  should open scrolled to.
//

import Foundation

public struct TeamSeasonSchedule: Equatable {
    public struct PhaseGroup: Equatable, Identifiable {
        public let season: String
        /// Nil for leagues without a preseason/playoff structure (soccer etc.) — the
        /// season is then one undivided list.
        public let phase: SeasonPhase?
        /// Oldest first.
        public let games: [Game]
        public var id: String { "\(season)|\(phase?.rawValue ?? "all")" }
    }

    public struct SeasonGroup: Equatable, Identifiable {
        public let season: String
        public let phases: [PhaseGroup]
        public var id: String { season }
        public var displayName: String { Game.seasonDisplayName(season) }
    }

    /// Oldest season first.
    public let seasons: [SeasonGroup]
    /// The game to open on: a game in progress, else the next one to be played, else the
    /// most recent game. Mid-season that lands mid-list, with results above and fixtures
    /// below; in the off-season it's the last result, or the next season's opener once
    /// that is scheduled.
    public let anchorGameID: String?

    public var isEmpty: Bool { seasons.isEmpty }

    public init(games: [Game], now: Date = Date()) {
        func date(_ game: Game) -> Date? {
            game.isoDate ?? game.strTimestamp.flatMap(DateParsers.parse)
        }

        // De-dupe by id (merged schedule + live copies), then date order. Undated games
        // sort last; ties keep a stable order by id so rows don't shuffle between renders.
        var seen = Set<String>()
        let ordered = games
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                switch (date(lhs), date(rhs)) {
                case let (l?, r?) where l != r: return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.id < rhs.id
                }
            }

        let usesPhases: (Game) -> Bool = { game in
            Leagues(rawValue: Int(game.idLeague ?? "") ?? -1)?.hasSeasonPhases ?? false
        }

        var seasonOrder: [String] = []
        var bySeason: [String: [Game]] = [:]
        for game in ordered {
            let season = game.resolvedSeason ?? "Other"
            if bySeason[season] == nil { seasonOrder.append(season) }
            bySeason[season, default: []].append(game)
        }

        seasons = seasonOrder.map { season in
            let seasonGames = bySeason[season] ?? []
            guard seasonGames.contains(where: usesPhases) else {
                return SeasonGroup(season: season, phases: [PhaseGroup(season: season, phase: nil, games: seasonGames)])
            }
            let byPhase = Dictionary(grouping: seasonGames, by: \.resolvedSeasonPhase)
            let phases = byPhase.keys.sorted().map { phase in
                PhaseGroup(season: season, phase: phase, games: byPhase[phase] ?? [])
            }
            return SeasonGroup(season: season, phases: phases)
        }

        // Games read in season/phase order, which is also what's on screen.
        let onScreen = seasons.flatMap { $0.phases.flatMap(\.games) }
        // A game still unfinished six hours after kickoff is a stale status, not "next".
        let staleCutoff = now.addingTimeInterval(-6 * 60 * 60)
        let next = onScreen.first { game in
            guard !game.isFinalStatus, !game.isCalledOff, let kickoff = date(game) else { return false }
            return kickoff >= staleCutoff
        }
        anchorGameID = (next ?? onScreen.last { date($0).map { $0 <= now } ?? false } ?? onScreen.last)?.id
    }
}

public extension TeamSeasonSchedule.PhaseGroup {
    /// "12–5" (or "12–5–1" with ties) from this team's finished games in the group;
    /// nil until a game with a score has been played.
    func record(forTeamID teamID: String?, teamNames: Set<String>) -> String? {
        var wins = 0, losses = 0, ties = 0
        for game in games where game.isFinalStatus {
            guard let home = game.intHomeScore.flatMap({ Int($0) }),
                  let away = game.intAwayScore.flatMap({ Int($0) }) else { continue }
            let isHome: Bool
            if let teamID, !teamID.isEmpty, game.idHomeTeam == teamID || game.idAwayTeam == teamID {
                isHome = game.idHomeTeam == teamID
            } else {
                isHome = teamNames.contains(game.strHomeTeam)
            }
            let (ours, theirs) = isHome ? (home, away) : (away, home)
            if ours > theirs { wins += 1 } else if ours < theirs { losses += 1 } else { ties += 1 }
        }
        guard wins + losses + ties > 0 else { return nil }
        return ties > 0 ? "\(wins)–\(losses)–\(ties)" : "\(wins)–\(losses)"
    }
}

public extension Game {
    /// Whether the game is over. Unlike `hasDoneStatus` — which also counts not-started
    /// statuses ("NS", "pre") and so really means "not live" — this is true only for a
    /// final: TheSportsDB's FT/AOT/AP/AET/PEN, ESPN's "post"/"Final…", or ESPN's
    /// completed flag.
    var isFinalStatus: Bool {
        if isCompleted == true { return true }
        // ESPN files a postponed game as state "post" with 0–0 scores; without this
        // it would render as a final tie and count one in the phase record.
        if isCalledOff { return false }
        return [strStatus, strProgress].contains { status in
            guard let status else { return false }
            return Self.finalStatuses.contains(status) || status.hasPrefix("Final")
        }
    }

    /// Postponed, cancelled or abandoned — neither upcoming nor a result.
    ///
    /// TheSportsDB puts it in `strStatus` (PST / CANC / ABD); ESPN leaves `strStatus`
    /// at "post" and says "Postponed" / "Canceled" in `strProgress`.
    var isCalledOff: Bool { calledOffKind != nil }

    /// Which way the game was called off, for display.
    var calledOffKind: CalledOffKind? {
        for value in [strStatus, strProgress] {
            guard let value, let kind = CalledOffKind(status: value) else { continue }
            return kind
        }
        return nil
    }

    private static let finalStatuses: Set<String> = ["FT", "AOT", "AP", "AET", "PEN", "post", "Match Finished"]
}

public enum CalledOffKind: String, Sendable {
    case postponed = "Postponed"
    case cancelled = "Cancelled"
    case abandoned = "Abandoned"

    init?(status: String) {
        switch status.lowercased() {
        case "pst", "postponed": self = .postponed
        case "canc", "cancelled", "canceled": self = .cancelled
        case "abd", "abandoned": self = .abandoned
        default: return nil
        }
    }
}
