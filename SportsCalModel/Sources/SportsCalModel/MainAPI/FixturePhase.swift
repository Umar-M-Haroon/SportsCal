//
//  FixturePhase.swift
//  SportsCalModel
//
//  Where a single game sits relative to the clock, judged from its kickoff time alone.
//  Widgets can't refresh often enough to show live scores, so instead of trusting a
//  possibly hours-old score they infer "likely live" from kickoff + a typical length.
//

import Foundation

public enum FixturePhase: Equatable {
    /// Kickoff is still ahead.
    case upcoming
    /// Kicked off within the sport's typical game length and not known to be over.
    case likelyLive
    /// Known to be complete, or past the point it would normally have finished.
    case ended
}

public extension SportType {
    /// Generous wall-clock length of a game, stoppages and overtime included. Used only
    /// to guess when a game is probably still going.
    var typicalGameLength: TimeInterval {
        switch self {
        case .soccer: return 2 * 60 * 60
        case .basketball: return 2.5 * 60 * 60
        case .hockey: return 2.75 * 60 * 60
        case .mlb: return 3 * 60 * 60
        case .nfl: return 3.5 * 60 * 60
        case .golf, .tennis, .racing: return 3 * 60 * 60
        }
    }
}

public enum FixtureSelection {
    public static func phase(kickoff: Date, isCompleted: Bool, length: TimeInterval, at now: Date) -> FixturePhase {
        if isCompleted { return .ended }
        if kickoff > now { return .upcoming }
        return now < kickoff.addingTimeInterval(length) ? .likelyLive : .ended
    }

    /// Picks the game worth showing for one team: a likely-live game first, then the
    /// next upcoming one, then a game that ended earlier today.
    public static func pick<G>(
        from games: [G],
        at now: Date,
        calendar: Calendar = .current,
        kickoff: (G) -> Date?,
        isCompleted: (G) -> Bool,
        length: (G) -> TimeInterval
    ) -> (game: G, phase: FixturePhase)? {
        let dated = games
            .compactMap { game in kickoff(game).map { (game: game, kickoff: $0) } }
            .sorted { $0.kickoff < $1.kickoff }
            .map { entry in
                (game: entry.game, kickoff: entry.kickoff,
                 phase: phase(kickoff: entry.kickoff, isCompleted: isCompleted(entry.game), length: length(entry.game), at: now))
            }

        if let live = dated.first(where: { $0.phase == .likelyLive }) { return (live.game, .likelyLive) }
        if let next = dated.first(where: { $0.phase == .upcoming }) { return (next.game, .upcoming) }
        if let today = dated.last(where: { $0.phase == .ended && calendar.isDate($0.kickoff, inSameDayAs: now) }) {
            return (today.game, .ended)
        }
        return nil
    }

    /// Moments after `now` when `phase` would change for a game — kickoff and the end
    /// of its typical length — so a timeline can flip state without a reload.
    public static func transitions(kickoff: Date, length: TimeInterval, after now: Date) -> [Date] {
        [kickoff, kickoff.addingTimeInterval(length)].filter { $0 > now }
    }
}
