//
//  RaceWeekend.swift
//  SportsCalModel
//
//  Where a race weekend stands: which session is the race, whether it's run, whether
//  the weekend is the one under way, and which session (if any) deserves emphasis.
//
//  A weekend's `strTimestamp` is its *first* session (FP1). Anything that reads it as
//  "when the race is" goes wrong: the São Paulo weekend vanished from "next event" on
//  its Saturday because FP1 was the day before, and a finished race's detail showed
//  Friday practice's time.
//

import Foundation

public extension Game {
    /// The race itself within the weekend's sessions ("Race"/"race"/"R").
    var raceSession: EventSession? {
        sessions?.first {
            let type = $0.sessionType.lowercased()
            return type == "race" || type == "r"
        }
    }

    /// When the race starts: the race session, else the last session, else the event date.
    var raceStartDate: Date? {
        if let date = raceSession?.startDate { return date }
        if let date = sessions?.compactMap(\.startDate).max() { return date }
        return isoDate ?? strTimestamp.flatMap(DateParsers.parse)
    }

    /// The race has been run. With sessions, only the race session's own status counts —
    /// a finished qualifying is not a finished weekend. Without them, the game's status.
    var isRaceFinished: Bool {
        if let race = raceSession {
            return race.status?.lowercased() == "post"
        }
        if let sessions, !sessions.isEmpty { return false }
        if isCompleted == true { return true }
        let status = strStatus?.lowercased()
        return status == "post" || status == "ft" || status == "final"
    }

    /// What to call P1 at the top of a race: the winner once the race is run, the
    /// leader before (practice, qualifying, or mid-race).
    var raceTopLabel: String {
        isRaceFinished ? "Winner" : "Leader"
    }

    /// The weekend is under way: it isn't finished, its first session has started or
    /// starts today, and race day is today or later. Future weekends are not.
    func isRaceWeekendInProgress(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isRace, !isRaceFinished else { return false }
        let startOfToday = calendar.startOfDay(for: now)
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return false }
        let starts = (sessions ?? []).compactMap(\.startDate)
        guard let first = starts.min() ?? isoDate ?? strTimestamp.flatMap(DateParsers.parse) else { return false }
        if sessions?.contains(where: { $0.status?.lowercased() == "in" }) == true { return true }
        guard first < endOfToday else { return false }
        return (raceStartDate ?? first) >= startOfToday
    }

    /// The session to emphasise in a weekend's session strip: the live one, else — only
    /// for the weekend under way — the next one to start. A future weekend highlights
    /// nothing; its FP1 isn't "current" just because it's first.
    func focusedRaceSession(now: Date = Date(), calendar: Calendar = .current) -> EventSession? {
        guard let sessions, !sessions.isEmpty else { return nil }
        if let live = sessions.first(where: { $0.status?.lowercased() == "in" }) { return live }
        guard isRaceWeekendInProgress(now: now, calendar: calendar) else { return nil }
        return sessions
            .filter { $0.status?.lowercased() != "post" }
            .compactMap { session -> (EventSession, Date)? in
                guard let date = session.startDate, date > now else { return nil }
                return (session, date)
            }
            .min { $0.1 < $1.1 }?.0
    }

    /// The date a summary ("next on", "N today") should file this event under. A race
    /// weekend files under race day, so a weekend whose practice ran yesterday is still
    /// today's or the next event until its race is run.
    var summaryDate: Date? {
        if isRace { return raceStartDate }
        return isoDate ?? strTimestamp.flatMap(DateParsers.parse)
    }

    /// The next event on or after the start of `now`'s day, by ``summaryDate``. An
    /// in-progress race weekend wins over a later one even though its FP1 has passed.
    static func nextEvent(in games: [Game], now: Date = Date(), calendar: Calendar = .current) -> Game? {
        let startOfToday = calendar.startOfDay(for: now)
        var best: (game: Game, date: Date)?
        for game in games {
            guard let date = game.summaryDate, date >= startOfToday else { continue }
            if game.isRace && game.isRaceFinished { continue }
            if let current = best, current.date <= date { continue }
            best = (game, date)
        }
        return best?.game
    }
}
