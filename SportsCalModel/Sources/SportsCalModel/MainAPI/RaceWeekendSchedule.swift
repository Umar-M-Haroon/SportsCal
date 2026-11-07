//
//  RaceWeekendSchedule.swift
//  SportsCalModel
//
//  How a race weekend reads in reminders, calendar entries and list rows: which
//  session a single reminder should time to, what to call it, and what's next.
//  A race weekend's `strTimestamp` is its first session (F1: FP1), and its
//  `strAwayTeam` is whoever leads, so the head-to-head wording ("Lando Norris @
//  Dutch Grand Prix") and timing every other sport uses are both wrong here.
//

import Foundation

public extension Game {
    /// The event's own start: `isoDate`, else the parsed timestamp.
    var scheduledStartDate: Date? {
        isoDate ?? strTimestamp.flatMap(DateParsers.parse)
    }

    /// For a race weekend, the session a single reminder or calendar entry means: the
    /// Race when listed, else the most important session. Nil for every other sport.
    var headlineSession: EventSession? {
        guard isRace, let sessions, !sessions.isEmpty else { return nil }
        // max(by:) keeps the last of equals; prefer the first-listed on ties.
        return sessions.reduce(nil) { best, session -> EventSession? in
            guard let best else { return session }
            return session.importance > best.importance ? session : best
        }
    }

    /// Reminder / calendar title. Race weekends read "Dutch Grand Prix — Race";
    /// tournaments use their name (a golf leader is not an opponent); head-to-head
    /// games keep "Away @ Home".
    func eventTitle(session: EventSession? = nil) -> String {
        if isRace {
            guard let session = session ?? headlineSession else { return strHomeTeam }
            return "\(strHomeTeam) — \(session.displayName)"
        }
        if isIndividualSport && !isTennisMatch {
            return tournamentName ?? strHomeTeam
        }
        return "\(strAwayTeam) @ \(strHomeTeam)"
    }

    /// When a reminder or calendar entry should start: the given session, else the
    /// weekend's headline session, else the event's own start.
    func eventStartDate(session: EventSession? = nil) -> Date? {
        (session ?? headlineSession)?.startDate ?? scheduledStartDate
    }

    /// Calendar entry length in hours: an hour for practice and qualifying, the
    /// clock for a timed endurance race, three for other races, two otherwise.
    func eventDurationHours(session: EventSession? = nil) -> Int {
        guard isRace, let session = session ?? headlineSession else { return 2 }
        if let duration = session.raceState?.duration, duration > 0 {
            return max(Int((duration / 3600).rounded(.up)), 1)
        }
        return session.isTimedLapSession ? 1 : 3
    }

    /// Sessions that haven't started yet, in start order.
    func upcomingSessions(after now: Date = Date()) -> [EventSession] {
        (sessions ?? [])
            .filter { $0.status != "in" && $0.status != "post" }
            .compactMap { session in session.startDate.map { (session, $0) } }
            .filter { $0.1 > now }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// The next session to start, if any.
    func nextSession(after now: Date = Date()) -> EventSession? {
        upcomingSessions(after: now).first
    }

    /// The session a race weekend's headline leaderboard comes from: the live one,
    /// else the most important finished one with results. Mirrors how the server
    /// picks `leaderboardEntries`, so a row can say where its top three came from.
    var featuredSession: EventSession? {
        guard isRace, let sessions else { return nil }
        if let live = sessions.first(where: { $0.status == "in" }) { return live }
        return sessions
            .filter { $0.status == "post" && !$0.leaderboard.isEmpty }
            .reduce(nil) { best, session -> EventSession? in
                guard let best else { return session }
                return session.importance >= best.importance ? session : best
            }
    }
}

public extension EventSession {
    /// Stable key for a per-session reminder ("race", "ss").
    var reminderKey: String {
        sessionType.isEmpty ? sessionName.lowercased() : sessionType.lowercased()
    }

    /// What to call P1: the winner of a finished race or sprint, the fastest of a
    /// timed session, the leader while running.
    var leaderTitle: String {
        if status == "post" { return isTimedLapSession ? "Fastest" : "Winner" }
        return isTimedLapSession ? "Fastest" : "Leader"
    }
}
