//
//  PeriodLabels.swift
//  SportsCalModel
//
//  One place that names a game's periods and knows how long they run. The play-by-play
//  picker, the box score, the momentum chart and clutch alerts used to keep their own
//  tables, and they disagreed: basketball OT read "Q5", a hockey 2OT read "SO", a
//  shootout read "OT2", and NCAA halves read Q1/Q2.
//
//  The season phase matters for hockey: the regular season (and preseason) settles a
//  tie with a 5-minute overtime and then a shootout, the playoffs with 20-minute
//  sudden-death overtimes that repeat until someone scores.
//

import Foundation

public extension Leagues {
    /// Periods in regulation: quarters, halves, periods or innings. Nil where it isn't
    /// a fixed count we reason about (soccer, individual sports).
    var regulationPeriods: Int? {
        switch self {
        case .nba, .wnba, .nfl, .ncaaf: return 4
        case .ncaaMBBTournament: return 2
        case .nhl: return 3
        case .mlb: return 9
        default: return nil
        }
    }

    /// Short label for a period, as tabs and box-score columns show it: "Q4", "H2",
    /// "P3", "OT", "2OT", "SO", "1H"/"ET1"/"PEN" for soccer, and "9" for an inning.
    func periodLabel(_ period: Int, phase: SeasonPhase? = nil) -> String {
        if isSoccer {
            let labels = ["1H", "2H", "ET1", "ET2", "PEN"]
            return (1...labels.count).contains(period) ? labels[period - 1] : "\(period)"
        }
        guard let regulation = regulationPeriods else { return "\(period)" }
        if self == .mlb { return "\(period)" }
        if period <= regulation {
            switch self {
            case .ncaaMBBTournament: return "H\(period)"
            case .nhl: return "P\(period)"
            default: return "Q\(period)"
            }
        }
        let overtime = period - regulation
        // Outside the playoffs an NHL game that's still tied after one overtime goes to
        // a shootout, which ESPN reports as the fifth period.
        if self == .nhl, phase != .postseason, overtime >= 2 { return "SO" }
        return overtime == 1 ? "OT" : "\(overtime)OT"
    }

    /// Label for a period in prose: like ``periodLabel(_:phase:)``, but innings read as
    /// ordinals ("9th"). Used by clutch alerts and win-probability boundaries.
    func periodName(_ period: Int, phase: SeasonPhase? = nil) -> String {
        if self == .mlb { return ClutchMoment.ordinal(period) }
        return periodLabel(period, phase: phase)
    }

    /// How long a period runs on the game clock, in seconds. Nil for untimed periods
    /// (innings, a shootout) and leagues without a fixed structure.
    func periodLengthSeconds(_ period: Int, phase: SeasonPhase? = nil) -> Double? {
        guard let regulation = regulationPeriods, self != .mlb else { return nil }
        let isOvertime = period > regulation
        switch self {
        case .nba: return isOvertime ? 5 * 60 : 12 * 60
        case .wnba: return isOvertime ? 5 * 60 : 10 * 60
        case .ncaaMBBTournament: return isOvertime ? 5 * 60 : 20 * 60
        // NFL regular-season OT is 10 minutes, playoff OT a full 15. College overtime
        // is untimed (alternating possessions from the 25).
        case .nfl: return isOvertime ? (phase == .postseason ? 15 * 60 : 10 * 60) : 15 * 60
        case .ncaaf: return isOvertime ? nil : 15 * 60
        case .nhl:
            guard isOvertime else { return 20 * 60 }
            if phase == .postseason { return 20 * 60 }
            return period - regulation == 1 ? 5 * 60 : nil
        default: return nil
        }
    }
}

public extension Game {
    /// This game's league, from `idLeague`.
    var leagueValue: Leagues? {
        idLeague.flatMap { Int($0) }.flatMap(Leagues.init(rawValue:))
    }

    /// Short label for one of this game's periods. See ``Leagues/periodLabel(_:phase:)``.
    func periodLabel(_ period: Int) -> String {
        // Old cached rows can lack `idLeague`; their sport still decides the shape.
        let league = leagueValue ?? sportType.flatMap { sport in
            sport == .soccer ? .English_Premier_League : ClutchMoment.defaultLeague(for: sport)
        }
        return league?.periodLabel(period, phase: resolvedSeasonPhase) ?? "\(period)"
    }

    /// Box-score column headers for `count` periods. Leagues without a fixed structure
    /// (golf, tennis sets) number them; racing counts laps.
    func periodLabels(count: Int) -> [String] {
        guard count > 0 else { return [] }
        if sportType == .racing { return (1...count).map { "Lap \($0)" } }
        return (1...count).map(periodLabel)
    }
}
