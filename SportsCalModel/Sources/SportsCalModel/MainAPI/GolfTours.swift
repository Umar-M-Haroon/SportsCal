//
//  GolfTours.swift
//  SportsCalModel
//
//  Golf is one league-agnostic bucket (`LiveScore.golf`) holding every tour's events, each
//  tagged with its tour in `idLeague`. `GolfTourBoard` splits that bucket back into tours for
//  Browse; `GolfPar` works out a course's par from the scores ESPN already sends.
//

import Foundation

public extension Leagues {
    /// Every golf tour, in the order Browse lists them: the PGA TOUR, the other two men's
    /// tours with majors-level fields, the LPGA, then the senior and development tours.
    static let golfTours: [Leagues] = [.pga, .dpWorld, .lpga, .livGolf, .championsTour, .kornFerry]

    /// Short label for a golf tour picker ("PGA", "DP World"…). Nil for non-golf leagues.
    var golfTourShortName: String? {
        switch self {
        case .pga:           return "PGA"
        case .dpWorld:       return "DP World"
        case .lpga:          return "LPGA"
        case .livGolf:       return "LIV"
        case .championsTour: return "Champions"
        case .kornFerry:     return "Korn Ferry"
        default:             return nil
        }
    }
}

public extension Game {
    /// The golf tour this event belongs to, or nil if it isn't a golf event.
    var golfTour: Leagues? {
        guard let raw = idLeague, let id = Int(raw), let league = Leagues(rawValue: id),
              league.isGolf else { return nil }
        return league
    }

    /// ESPN dates a multi-day event with day *markers* — midnight US Eastern (04:00Z) — not
    /// a tee time. Shifting both ends by 7h lands them inside their intended local day
    /// everywhere from Hawaii to New Zealand. Mirrors the app's `Game.occursOn`.
    private static let espnDayMarkerShift: TimeInterval = 7 * 60 * 60

    /// First and last day of the event, as instants inside those days. A multi-day event
    /// (a golf tournament's Thursday–Sunday) is shifted off its day markers; a single-day
    /// event is its start on both ends. Nil without a start date.
    var eventDaySpan: (first: Date, last: Date)? {
        guard let start = isoDate ?? strTimestamp.flatMap(DateParsers.parse) else { return nil }
        if let end = endDateParsed, end > start {
            return (start.addingTimeInterval(Self.espnDayMarkerShift), end.addingTimeInterval(Self.espnDayMarkerShift))
        }
        return (start, start)
    }
}

/// Splits the golf bucket into tours and each tour into its schedule and results.
public enum GolfTourBoard {
    /// Tours that have at least one event in `games`, in `Leagues.golfTours` order.
    public static func tours(in games: [Game]) -> [Leagues] {
        let present = Set(games.compactMap(\.golfTour))
        return Leagues.golfTours.filter(present.contains)
    }

    /// The tour to open on: the first tour with events that the user hasn't hidden, else the
    /// first tour with events at all (Browse still lets you look at a hidden tour).
    public static func defaultTour(in tours: [Leagues], hidden: Set<String>) -> Leagues? {
        tours.first { !hidden.contains($0.leagueName) } ?? tours.first
    }

    /// `tour`'s events, one per tournament. The same event can reach the client twice (the
    /// schedule row and the live row), so later copies of an `idEvent` are dropped.
    public static func events(for tour: Leagues, in games: [Game]) -> [Game] {
        var seen = Set<String>()
        return games.filter { game in
            guard game.golfTour == tour else { return false }
            guard let id = game.idEvent else { return true }
            return seen.insert(id).inserted
        }
    }

    /// Events still to finish — live now, or whose last day is today or later — live first,
    /// then soonest start.
    public static func upcoming(_ events: [Game], startOfToday: Date) -> [Game] {
        events
            .filter { isLive($0) || ($0.eventDaySpan?.last ?? .distantFuture) >= startOfToday }
            .sorted {
                if isLive($0) != isLive($1) { return isLive($0) }
                return ($0.eventDaySpan?.first ?? .distantFuture) < ($1.eventDaySpan?.first ?? .distantFuture)
            }
    }

    /// Finished events, most recent first.
    public static func past(_ events: [Game], startOfToday: Date) -> [Game] {
        events
            .filter { !isLive($0) && ($0.eventDaySpan?.last ?? .distantFuture) < startOfToday }
            .sorted { ($0.eventDaySpan?.last ?? .distantPast) > ($1.eventDaySpan?.last ?? .distantPast) }
    }

    public static func isLive(_ game: Game) -> Bool {
        game.strStatus?.lowercased() == "in"
    }
}

/// Course par, from data where we have it.
public enum GolfPar {
    /// Infers par from completed rounds: ESPN gives each round's strokes (`value`, 65) and its
    /// score to par (`displayValue`, "-6"), so strokes minus to-par is the par. Every completed
    /// round on the course agrees, so the most common answer wins; a round still in progress
    /// (par of only the holes played) or a withdrawal is an outlier. Needs at least two
    /// agreeing rounds and a clear winner, and ignores anything outside a plausible 18-hole
    /// par, so a feed that puts strokes in `displayValue` can't produce a par.
    public static func inferred(fromRounds rounds: [(strokes: Double?, toPar: String?)]) -> Int? {
        var counts: [Int: Int] = [:]
        for round in rounds {
            guard let strokes = round.strokes, let toPar = round.toPar.flatMap(parseToPar) else { continue }
            let par = Int(strokes.rounded()) - toPar
            guard plausiblePar.contains(par) else { continue }
            counts[par, default: 0] += 1
        }
        let ranked = counts.sorted { $0.value > $1.value }
        guard let best = ranked.first, best.value >= 2 else { return nil }
        if ranked.count > 1, ranked[1].value == best.value { return nil }
        return best.key
    }

    /// Par of a regulation 18-hole course. Real courses sit at 69–73; the margin is slack,
    /// not a guess at any particular course.
    static let plausiblePar = 66...74

    /// "E" → 0, "-6" → -6, "+2" → 2. Nil for anything else ("--", "CUT", "F").
    static func parseToPar(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.uppercased() == "E" { return 0 }
        return Int(trimmed.hasPrefix("+") ? String(trimmed.dropFirst()) : trimmed)
    }

    /// Par for events whose course never changes, for when the feed hasn't given us one yet
    /// (before the first round is complete). Only the Masters qualifies: every other major
    /// rotates venues, and par changes with the venue (the PGA Championship, U.S. Open and
    /// The Open have all been played at par 70 and 71 as well as 72).
    public static func fixedVenuePar(eventName: String, tour: Leagues?) -> Int? {
        // DP World's "European Masters", "British Masters", "Qatar Masters" are not Augusta;
        // on the PGA board the Masters is the only one (the same match `EventTierTable` uses).
        guard tour == nil || tour == .pga else { return nil }
        return eventName.lowercased().contains("masters") ? 72 : nil
    }
}
