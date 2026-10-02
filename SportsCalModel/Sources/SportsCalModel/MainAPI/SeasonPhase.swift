//
//  SeasonPhase.swift
//  SportsCalModel
//
//  Which part of a league's season a game belongs to, plus the season it belongs to.
//  Drives the team page's season → phase grouping.
//

import Foundation

/// Where a game sits in its league's season.
///
/// Only leagues with a preseason/playoff structure get one (``Leagues/hasSeasonPhases``).
/// The schedule omits `.regular` on the wire to keep the payload small, so read
/// ``Game/resolvedSeasonPhase`` rather than ``Game/seasonPhase`` directly.
public enum SeasonPhase: String, Codable, Sendable, CaseIterable, Comparable {
    case preseason = "pre"
    case regular = "reg"
    case playIn = "playin"
    case postseason = "post"

    public var displayName: String {
        switch self {
        case .preseason:  return "Preseason"
        case .regular:    return "Regular Season"
        case .playIn:     return "Play-In"
        case .postseason: return "Playoffs"
        }
    }

    private var order: Int {
        switch self {
        case .preseason:  return 0
        case .regular:    return 1
        case .playIn:     return 2
        case .postseason: return 3
        }
    }

    public static func < (lhs: SeasonPhase, rhs: SeasonPhase) -> Bool { lhs.order < rhs.order }

    /// TheSportsDB's `intRound` codes for the US leagues: 500 is preseason, 400 the NBA
    /// play-in, and 100…499 the playoff rounds (125 wild card / first round, 150, 160,
    /// 170, 180, 200 = final). Week numbers 0…99 are regular season — though TheSportsDB
    /// also files some playoff games under ordinary week numbers, which
    /// ``assignPhases(_:league:)`` corrects by date.
    public init(sportsDBRound round: Int) {
        switch round {
        case 500:      self = .preseason
        case 400:      self = .playIn
        case 100..<500: self = .postseason
        default:       self = .regular
        }
    }

    /// ESPN's `season.type`: 1 preseason, 2 regular, 3 postseason, 5 play-in.
    /// 4 (off-season) and anything unknown return nil.
    public init?(espnSeasonType type: Int) {
        switch type {
        case 1: self = .preseason
        case 2: self = .regular
        case 3: self = .postseason
        case 5: self = .playIn
        default: return nil
        }
    }

    /// Stamps `seasonPhase` on a league's TheSportsDB schedule from each row's
    /// `sportsDBRound`, then fixes the playoff games TheSportsDB files under ordinary
    /// week numbers.
    ///
    /// The fix: in Sep 2026 TheSportsDB's 2025-26 NHL feed had ~100 first-round playoff
    /// games as "round 16" and the NBA's as rounds 0 and 1, while every league's final
    /// regular-season week carries the highest week number. So each season's regular
    /// season ends on the last date of its highest-numbered week, and any week-numbered
    /// game after that day is a playoff game. The NBA Cup final (round 0, December) sits
    /// well before that cutoff and stays regular.
    public static func assignPhases(_ games: [Game], league: Leagues) -> [Game] {
        guard league.hasSeasonPhases else { return games }

        var stamped = games.map { game -> Game in
            var game = game
            if let round = game.sportsDBRound {
                game.seasonPhase = SeasonPhase(sportsDBRound: round)
            }
            return game
        }

        // Regular-season end per season = latest kickoff in its highest-numbered week.
        var lastWeek: [String: (week: Int, end: Date)] = [:]
        for game in stamped {
            guard let season = game.season, let round = game.sportsDBRound,
                  (1..<100).contains(round), let date = game.isoDate ?? game.strTimestamp.flatMap(DateParsers.parse) else { continue }
            if let current = lastWeek[season] {
                if round > current.week {
                    lastWeek[season] = (round, date)
                } else if round == current.week, date > current.end {
                    lastWeek[season] = (round, date)
                }
            } else {
                lastWeek[season] = (round, date)
            }
        }

        // A day of slack so a late West Coast finale on the last date isn't caught.
        for index in stamped.indices {
            let game = stamped[index]
            guard game.seasonPhase == .regular, let season = game.season,
                  let end = lastWeek[season]?.end, let date = game.isoDate ?? game.strTimestamp.flatMap(DateParsers.parse),
                  date > end.addingTimeInterval(24 * 60 * 60) else { continue }
            stamped[index].seasonPhase = .postseason
        }
        return stamped
    }
}

public extension Leagues {
    /// Leagues with a preseason → regular season → playoffs structure.
    var hasSeasonPhases: Bool {
        switch self {
        case .nba, .nhl, .mlb, .nfl, .wnba, .MLS: return true
        default: return false
        }
    }

    /// The season a game on `date` belongs to, in TheSportsDB's label format. Only a
    /// fallback for games that arrive without one (ESPN-only rows, older servers).
    ///
    /// Single-year leagues use the calendar year, except the NFL, whose season runs
    /// into February. Split-year leagues turn over in July, ahead of every preseason.
    func seasonLabel(for date: Date, calendar: Calendar = .current) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        if sportsDBSingleYearSeason {
            if self == .nfl, month < 3 { return "\(year - 1)" }
            return "\(year)"
        }
        return month >= 7 ? "\(year)-\(year + 1)" : "\(year - 1)-\(year)"
    }

    /// The season label for ESPN's `season.year`, which is the year a split-year
    /// season ends in (2027 = 2026-27). Nil for leagues where ESPN's year convention
    /// isn't known to match — those fall back to ``seasonLabel(for:calendar:)``.
    func seasonLabel(espnYear year: Int) -> String? {
        switch self {
        case .mlb, .nfl, .wnba, .MLS: return "\(year)"
        case .nba, .nhl:             return "\(year - 1)-\(year)"
        default:                     return nil
        }
    }
}

public extension Game {
    /// The phase to display: the stamped phase, else a playoff game by its playoff
    /// context, else regular season. (The wire format omits `.regular`.)
    var resolvedSeasonPhase: SeasonPhase {
        if let seasonPhase { return seasonPhase }
        return playoff != nil ? .postseason : .regular
    }

    /// The season to group this game under — the stamped season, else one derived
    /// from its date. Nil only when the game has neither a league nor a date.
    var resolvedSeason: String? {
        if let season, !season.isEmpty { return season }
        guard let date = isoDate ?? strTimestamp.flatMap(DateParsers.parse) else { return nil }
        let league = Leagues(rawValue: Int(idLeague ?? "") ?? -1)
        return (league ?? .nba).seasonLabel(for: date)
    }

    /// "2025–26 Season" / "2025 Season" for a TheSportsDB season label.
    static func seasonDisplayName(_ season: String) -> String {
        let parts = season.split(separator: "-")
        if parts.count == 2, parts[1].count == 4 {
            return "\(parts[0])–\(parts[1].suffix(2)) Season"
        }
        return "\(season) Season"
    }
}
