//
//  Teams+Extensions.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/24/22.
//

import Foundation
import SportsCalModel

extension Team {
    static func getTeamInfoFrom(teams: [Team], teamID: String?) -> Team? {
        let defaultTeam = teams.first { team in
            team.idTeam == teamID && team.strTeamShort != nil
        }
        return defaultTeam ?? teams.first { team in
            team.idTeam == teamID
        }
    }
    static func getTeamInfoFrom(teamDict: [String?: [Team]], teamID: String?) -> Team? {
        return teamDict[teamID]?.first(where: {$0.strTeamShort != nil}) ?? teamDict[teamID]?.first
    }
    
    static func getTeamInfoFrom(teams: [Team], teamName: String?) -> Team? {
        let defaultTeam = teams.first { team in
            team.strTeam == teamName && team.strTeamShort != nil
        }
        return defaultTeam ?? teams.first { team in
            team.strTeam == teamName
        }
    }
    
    static func getTeamInfoFrom(teamDict: [String?: [Team]], teamName: String?) -> Team? {
        return teamDict[teamName]?.first(where: {$0.strTeamShort != nil}) ?? teamDict[teamName]?.first
    }

    /// Collision-safe lookup: ID match is only accepted if the team name also matches.
    /// ESPN and TheSportsDB IDs live in the same namespace, so a raw ID match can return
    /// the wrong team from a different sport. Callers pass the game's team name so we can
    /// validate the match and fall back to a name-based lookup when the IDs collide.
    static func getTeamInfoFrom(teams: [Team], teamID: String?, teamName: String?) -> Team? {
        if teamID != nil, let match = teams.first(where: { $0.idTeam == teamID && $0.strTeam == teamName && $0.strTeamShort != nil }) {
            return match
        }
        if teamID != nil, let match = teams.first(where: { $0.idTeam == teamID && $0.strTeam == teamName }) {
            return match
        }
        if let match = teams.first(where: { $0.strTeam == teamName && $0.strTeamShort != nil }) {
            return match
        }
        return teams.first(where: { $0.strTeam == teamName })
    }
}

extension Game {
    /// Read on every row render, in every sort comparator, and in every filter pass.
    ///
    /// It used to fall back to `getDate(dateFormatter:isoFormatter:)`, which reassigns
    /// `dateFormat` on the shared `DateFormatters.backupISOFormatter` up to three times
    /// per call while probing formats — rebuilding the underlying `CFDateFormatter` each
    /// time, and racing whenever the WebSocket decode task and the main actor both got
    /// there at once. `DateParsers` tries the same formats against formatters that are
    /// configured once, so this is the same answer without the mutation.
    ///
    /// In practice the fallback almost never runs: both `Game.init` and its `Codable`
    /// decoder already populate `isoDate` from `strTimestamp` via `DateParsers`.
    var standardDate: Date? {
        if let isoDate { return isoDate }
        guard let strTimestamp else { return nil }
        return DateParsers.parse(strTimestamp)
    }

    /// For multi-session events (F1), returns the last session's date (e.g. Race day)
    /// so the event appears under the correct day. Falls back to standardDate.
    var effectiveEndDate: Date? {
        if let lastDate = sessions?.last?.startDate {
            return lastDate
        }
        // A golf tournament's final round, so "hide past events" doesn't drop it on Friday.
        if let eventEndDate { return eventEndDate }
        return standardDate
    }

    /// Whether the user hid this game's competition (`hiddenCompetitions` holds league
    /// names). Tennis goes by the draw rather than `idLeague`: every match ships once as
    /// ATP and once as WTA, so the league alone would leave half of a hidden tour's matches
    /// showing. A mixed-doubles match belongs to both tours and stays until both are hidden.
    func isInHiddenCompetition<S: Sequence<String>>(_ hidden: S) -> Bool {
        if sportType == .tennis {
            let tours = tennisTours
            return !tours.isEmpty && tours.allSatisfy { hidden.contains($0.leagueName) }
        }
        guard let raw = idLeague, let id = Int(raw), let league = Leagues(rawValue: id) else { return false }
        return hidden.contains(league.leagueName)
    }

    /// Last day of a multi-day event (a golf tournament's Sunday), when the source
    /// gave us one.
    var eventEndDate: Date? {
        guard let endDate else { return nil }
        return DateParsers.parse(endDate)
    }

    /// ESPN dates a multi-day event with day *markers* — midnight US Eastern, i.e. 04:00Z
    /// — not a tee time. Read in a western zone that instant is still the previous
    /// evening, which would put a Thursday–Sunday tournament on Wednesday–Saturday.
    /// Shifting by 7h lands both ends inside their intended local day everywhere from
    /// Hawaii to New Zealand.
    private static let dayMarkerShift: TimeInterval = 7 * 60 * 60

    /// Whether this event is on the calendar day starting at `dayStart` (exclusive
    /// `dayEnd`). A golf tournament runs Thursday to Sunday and an F1 weekend has
    /// sessions on several days, so both stay on the board every day they run instead
    /// of showing only on the day they began.
    func occursOn(dayStart: Date, dayEnd: Date) -> Bool {
        if isRace, !sessionDates.isEmpty {
            return sessionDates.contains { $0 >= dayStart && $0 < dayEnd }
        }
        guard let start = standardDate else { return false }
        if let end = eventEndDate, end > start {
            let first = start.addingTimeInterval(Self.dayMarkerShift)
            let last = end.addingTimeInterval(Self.dayMarkerShift)
            return first < dayEnd && last >= dayStart
        }
        return start >= dayStart && start < dayEnd
    }

    /// All dates this event spans (for multi-session events like F1 weekends).
    /// Returns each unique calendar day from the first to last session.
    var sessionDates: [Date] {
        guard let sessions = sessions, !sessions.isEmpty else {
            return [standardDate].compactMap { $0 }
        }
        return sessions.compactMap(\.startDate)
    }

    /// User-facing status text. Prefers `strProgress` (e.g. "6:43 - 3rd", "Final Round"),
    /// falls back to `strStatus`. Hides raw state codes ("pre", "in", "NS") and
    /// normalizes completion codes ("FT", "AET", "post", …) to "Final".
    var displayStatus: String? {
        if let progress = normalizeStatus(strProgress) { return progress }
        return normalizeStatus(strStatus)
    }

    private func normalizeStatus(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
            return nil
        }
        let lower = trimmed.lowercased()
        switch lower {
        case "pre", "ns", "not started", "in":
            return nil
        case "ft", "ap", "post", "final", "match finished":
            return "Final"
        case "aet", "aot", "final/ot":
            return "Final (OT)"
        default:
            return trimmed
        }
    }
}

// MARK: - F1 Weekend Status

/// Session-aware status for an F1 race weekend. Avoids collapsing a multi-session
/// weekend into a single scalar (which made a *completed qualifying* — whose ESPN
/// `shortDetail` is literally "Final" — read as if the whole weekend was over).
enum RaceWeekendStatus {
    /// A session is currently running (e.g. "Qualifying", "Race").
    case live(String)
    /// The Race session has completed.
    case finished
    /// The race hasn't run yet — show the next session and when it starts.
    case upcoming(label: String, date: Date)
    /// Not a race weekend, or no session data.
    case none
}

extension Game {
    /// The Race session within the weekend, if present (case-insensitive match).
    var raceSessionEntry: EventSession? {
        sessions?.first { $0.sessionType.caseInsensitiveCompare("Race") == .orderedSame }
    }

    /// The session currently in progress, if any.
    var liveSessionEntry: EventSession? {
        sessions?.first { $0.status?.lowercased() == "in" }
    }

    /// The earliest session that hasn't started yet (not `post`/`in`, dated in the future).
    var nextUpcomingSession: EventSession? {
        guard let sessions, !sessions.isEmpty else { return nil }
        let now = Date()
        return sessions
            .filter { session in
                let status = session.status?.lowercased()
                return status != "post" && status != "in"
            }
            .compactMap { session -> (EventSession, Date)? in
                guard let date = session.startDate, date > now else { return nil }
                return (session, date)
            }
            .min { $0.1 < $1.1 }?.0
    }

    /// Long-form display name for an F1 session type abbreviation.
    func sessionDisplayName(_ type: String) -> String {
        switch type.lowercased() {
        case "fp1", "practice 1": return "Practice 1"
        case "fp2", "practice 2": return "Practice 2"
        case "fp3", "practice 3": return "Practice 3"
        case "qual", "qualifying": return "Qualifying"
        case "sprint": return "Sprint"
        case "sprint qualifying", "sprint shootout", "sq", "ss": return "Sprint Qualifying"
        case "race", "r": return "Race"
        default: return type.isEmpty ? "Session" : type
        }
    }

    /// Status to surface for a race weekend. "Final" is reported **only** once the Race
    /// session itself is complete — never from a finished qualifying.
    var raceWeekendStatus: RaceWeekendStatus {
        guard isRace, let sessions, !sessions.isEmpty else { return .none }
        if let live = liveSessionEntry {
            return .live(sessionDisplayName(live.sessionType))
        }
        if raceSessionEntry?.status?.lowercased() == "post" {
            return .finished
        }
        if let next = nextUpcomingSession, let date = next.startDate {
            return .upcoming(label: sessionDisplayName(next.sessionType), date: date)
        }
        return .none
    }
}

// MARK: - Schedule state

/// Where a game sits relative to now, for splitting schedules into upcoming / live /
/// results. `hasDoneStatus` can't do this on its own: it means "not in progress", so it
/// is also true for `pre`/`NS` games that haven't started.
enum GameScheduleState {
    case upcoming, live, final
}

extension Game {
    /// A status stuck on "in" this long after kickoff is stale — the match is over.
    private static let staleLiveInterval: TimeInterval = 6 * 60 * 60

    /// Classifies the game. `liveIDs` (the ids in `GameViewModel.liveEvents`) wins over
    /// the stored status, which lags the live feed.
    func scheduleState(liveIDs: Set<String> = [], now: Date = Date()) -> GameScheduleState {
        if liveIDs.contains(id) { return .live }
        let status = (strStatus ?? "").lowercased()
        let progress = (strProgress ?? "").lowercased()
        let date = standardDate
        if status == "pre" || status == "ns" || status == "not started" || progress == "pre" {
            // "Not started" hours after kickoff means postponed or a status that never
            // updated — either way it's no longer the next game.
            if let date, now.timeIntervalSince(date) > 3 * 60 * 60 { return .final }
            return .upcoming
        }
        if status == "in" {
            if let date, now.timeIntervalSince(date) > Self.staleLiveInterval { return .final }
            return .live
        }
        if hasDoneStatus { return .final }
        guard let date else { return .upcoming }
        if date > now { return .upcoming }
        return now.timeIntervalSince(date) < Self.staleLiveInterval && isCompleted != true ? .live : .final
    }
}

// MARK: - Seasons

extension Leagues {
    /// Leagues whose season straddles New Year and is named for both years ("2025–26").
    var hasSplitYearSeason: Bool {
        switch self {
        case .English_Premier_League, .English_League_Championship, .German_Bundesliga,
             .Serie_A, .Ligue_1, .La_Liga, .Eredivisie, .Liga_MX, .A_League,
             .UEFA_Champions_League, .UEFA_Europa_League, .UEFA_Conference_League,
             .FA_Cup, .Copa_del_Rey, .Coupe_De_France, .DFB_Pokal,
             .nba, .nhl:
            return true
        default:
            return false
        }
    }
}

extension Game {
    /// The season this game belongs to, labelled the way the league names it:
    /// "2025–26" for leagues that straddle New Year, "2025" for the NFL (named for the
    /// year it kicks off, so January playoffs stay in it) and calendar-year leagues.
    var seasonLabel: String? {
        guard let date = standardDate else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let league = idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:))
        if league?.hasSplitYearSeason == true {
            let start = month >= 7 ? year : year - 1
            return "\(start)–\(String(format: "%02d", (start + 1) % 100))"
        }
        if league == .nfl {
            return String(month >= 3 ? year : year - 1)
        }
        return String(year)
    }
}
