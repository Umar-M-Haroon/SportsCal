//
//  WidgetTourFilter.swift
//  SportsCalModel
//
//  Tour/league narrowing for widgets: which leagues a widget's explicit league pick hides,
//  how a hidden-league set applies to tennis matches (whose tour comes from the draw, not
//  the board they were fetched from), and which golf event a tour-pinned leaderboard shows.
//

import Foundation

public enum WidgetTourFilter {

    // MARK: - League picks

    /// League names hidden by a widget's explicit league pick, or `nil` when nothing is
    /// picked (the caller then falls back to the app's `hiddenCompetitions`).
    ///
    /// Soccer and tennis have always been narrowed as one group: picking any of them hides
    /// every soccer and tennis league not picked. Placed widgets depend on that, so it
    /// stays. Golf tours were added later and only narrow when a golf tour is picked —
    /// otherwise every existing soccer/tennis pick would silently lose golf.
    public static func hiddenLeagueNames(selected: Set<Leagues>) -> Set<String>? {
        guard !selected.isEmpty else { return nil }
        var universe = Leagues.allCases.filter { $0.isSoccer || $0.isTennis }
        if selected.contains(where: \.isGolf) {
            universe += Leagues.allCases.filter(\.isGolf)
        }
        return Set(universe.filter { !selected.contains($0) }.map(\.leagueName))
    }

    /// Drops games whose league is in `hidden`. Tennis matches go by `tennisTours`, so a
    /// women's match cached under the ATP board is hidden with the WTA, and a mixed-doubles
    /// match shows while either tour does. A match that shipped once per tour board (same
    /// `idEvent`) is kept once — the first *visible* copy, so a draw-less match whose first
    /// copy sits on a hidden board still shows from the other one.
    public static func filter(_ games: [Game], hidingLeagues hidden: Set<String>) -> [Game] {
        var seenTennis = Set<String>()
        return games.filter { game in
            let tours = game.tennisTours
            if !tours.isEmpty, game.isTennisMatch {
                guard tours.contains(where: { !hidden.contains($0.leagueName) }) else { return false }
                guard let id = game.idEvent else { return true }
                return seenTennis.insert(id).inserted
            }
            guard !hidden.isEmpty, let name = game.strLeague else { return true }
            return !hidden.contains(name)
        }
    }

    // MARK: - Golf leaderboard

    /// `games` on `tour`, or all of them when `tour` is nil.
    public static func games(_ games: [Game], on tour: Leagues?) -> [Game] {
        guard let tour else { return games }
        let id = String(tour.rawValue)
        return games.filter { $0.idLeague == id }
    }

    /// The in-progress event a leaderboard widget should feature from the live golf bucket:
    /// one with a leaderboard, on `tour` if given. Several tours play the same week,
    /// so with no tour it's the biggest event rather than whichever one ESPN listed first.
    public static func featuredLiveGolfEvent(_ events: [Game], tour: Leagues?) -> Game? {
        games(events, on: tour)
            .filter { !$0.resolvedLeaderboard.isEmpty }
            .max { ($0.eventTier ?? .tour) < ($1.eventTier ?? .tour) }
    }

    /// Fallback when nothing is live: the earliest non-cancelled golf event on `tour`,
    /// preferring one that already has a leaderboard.
    public static func scheduledGolfEvent(_ games: [Game], tour: Leagues?) -> Game? {
        let cancelled: Set<String> = ["cancelled", "canceled", "postponed", "suspended", "abandoned", "match finished"]
        let events = self.games(games.filter { $0.sportType == .golf }, on: tour)
            .filter { game in
                guard let status = game.strStatus?.lowercased() else { return true }
                return !cancelled.contains(status)
            }
            .sorted { startDate(of: $0) < startDate(of: $1) }
        return events.first { !$0.resolvedLeaderboard.isEmpty } ?? events.first
    }

    /// Same as the app's `standardDate`, which lives outside the package.
    private static func startDate(of game: Game) -> Date {
        game.isoDate ?? game.strTimestamp.flatMap(DateParsers.parse) ?? .distantFuture
    }
}
