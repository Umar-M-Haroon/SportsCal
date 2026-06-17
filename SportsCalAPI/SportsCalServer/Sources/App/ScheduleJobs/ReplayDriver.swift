//
//  ReplayDriver.swift
//  SportsCalServer
//
//  Developer-only: turns a finished game's recorded play-by-play into an ordered
//  sequence of `LiveScore` frames that the `/replay/:eventID` WebSocket streams back
//  to the client, reproducing the game as if it were live. Pure + synchronous so it
//  is trivially unit-testable; pacing/IO lives in the route.
//

import Foundation
import SportsCalModel

/// First WebSocket frame the client sends to `/replay`: the game "shell" plus, optionally,
/// the play-by-play the client already fetched (e.g. from production, where the data lives).
/// When `plays` is absent/empty the server resolves them itself via `PlayResolver`.
struct ReplayHandshake: Codable {
    let shell: Game
    let plays: [Play]?
}

enum ReplayDriver {
    /// Which `LiveScore` sport slot a replayed game belongs in. Replay is supported
    /// only for the team sports ESPN play-by-play covers.
    enum SportSlot {
        case nba, mlb, soccer, nfl, nhl
    }

    /// Maps a game shell to its `LiveScore` slot, or `nil` for unsupported sports
    /// (golf / tennis / F1 have no play timeline to replay).
    static func slot(for shell: Game) -> SportSlot? {
        guard let league = league(for: shell) else { return nil }
        if league.isBasketball { return .nba }
        if league == .nfl { return .nfl }
        if league == .nhl { return .nhl }
        if league == .mlb { return .mlb }
        if league.isSoccer { return .soccer }
        return nil
    }

    /// The ESPN `(sport, league)` slugs used to fetch a summary on demand when the
    /// play-by-play isn't already cached/archived.
    static func espnSportLeague(for shell: Game) -> (sport: String, league: String)? {
        guard let league = league(for: shell) else { return nil }
        if league.isBasketball { return ("basketball", league.espnSlug ?? "nba") }
        if league == .nfl { return ("football", "nfl") }
        if league == .nhl { return ("hockey", "nhl") }
        if league == .mlb { return ("baseball", "mlb") }
        if league.isSoccer, let slug = league.espnSlug { return ("soccer", slug) }
        return nil
    }

    private static func league(for shell: Game) -> Leagues? {
        guard let idLeague = shell.idLeague, let leagueInt = Int(idLeague) else { return nil }
        return Leagues(rawValue: leagueInt)
    }

    /// Builds the ordered list of `LiveScore` frames replaying `plays` over `shell`.
    /// Each frame carries the running score / clock / last play; the final frame is
    /// marked completed (`post`).
    static func snapshots(shell: Game, plays: [Play], slot: SportSlot) -> [LiveScore] {
        guard !plays.isEmpty else { return [] }
        var frames: [LiveScore] = []
        frames.reserveCapacity(plays.count)

        var lastHome = shell.intHomeScore ?? "0"
        var lastAway = shell.intAwayScore ?? "0"

        for (idx, play) in plays.enumerated() {
            if let h = play.homeScore { lastHome = String(h) }
            if let a = play.awayScore { lastAway = String(a) }
            let isFinal = idx == plays.count - 1
            let game = frame(
                from: shell,
                home: lastHome,
                away: lastAway,
                status: isFinal ? "post" : "in",
                progress: progressString(for: play, slot: slot, isFinal: isFinal),
                lastPlay: play.text,
                isCompleted: isFinal
            )
            frames.append(liveScore(with: game, slot: slot))
        }
        return frames
    }

    // MARK: - Frame construction

    private static func frame(
        from shell: Game,
        home: String,
        away: String,
        status: String,
        progress: String,
        lastPlay: String?,
        isCompleted: Bool
    ) -> Game {
        Game(
            idLiveScore: shell.idLiveScore,
            idEvent: shell.idEvent,
            idLeague: shell.idLeague,
            idHomeTeam: shell.idHomeTeam,
            idAwayTeam: shell.idAwayTeam,
            strHomeTeam: shell.strHomeTeam,
            strAwayTeam: shell.strAwayTeam,
            strHomeTeamBadge: shell.strHomeTeamBadge,
            strAwayTeamBadge: shell.strAwayTeamBadge,
            intHomeScore: home,
            intAwayScore: away,
            strStatus: status,
            strProgress: progress,
            strTimestamp: shell.strTimestamp,
            lastPlay: lastPlay,
            isCompleted: isCompleted,
            isoDate: shell.isoDate,
            venueName: shell.venueName,
            homeSeed: shell.homeSeed,
            awaySeed: shell.awaySeed,
            tournamentName: shell.tournamentName,
            round: shell.round,
            playoff: shell.playoff
        )
    }

    private static func liveScore(with game: Game, slot: SportSlot) -> LiveScore {
        let event = LiveEvent(events: [game])
        switch slot {
        case .nba: return LiveScore(nba: event)
        case .mlb: return LiveScore(mlb: event)
        case .soccer: return LiveScore(soccer: event)
        case .nfl: return LiveScore(nfl: event)
        case .nhl: return LiveScore(nhl: event)
        }
    }

    /// Human-readable progress string (e.g. "Q3 6:43", "P2 12:01", "Inn 7", "34'").
    static func progressString(for play: Play, slot: SportSlot, isFinal: Bool) -> String {
        if isFinal { return "Final" }
        let clock = play.clock?.displayValue
        let period = play.period?.number

        switch slot {
        case .soccer:
            // ESPN soccer clocks are already minute strings like "34'".
            if let clock, !clock.isEmpty { return clock }
            if let period { return period == 1 ? "1st Half" : "2nd Half" }
            return "Live"
        case .mlb:
            if let period { return "Inn \(period)" }
            return "Live"
        case .nhl:
            return periodClock(prefix: "P", period: period, clock: clock)
        case .nba, .nfl:
            return periodClock(prefix: "Q", period: period, clock: clock)
        }
    }

    private static func periodClock(prefix: String, period: Int?, clock: String?) -> String {
        switch (period, clock) {
        case let (.some(p), .some(c)) where !c.isEmpty: return "\(prefix)\(p) \(c)"
        case let (.some(p), _): return "\(prefix)\(p)"
        case let (_, .some(c)) where !c.isEmpty: return c
        default: return "Live"
        }
    }
}
