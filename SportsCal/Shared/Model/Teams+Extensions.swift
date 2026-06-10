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
    var standardDate: Date? {
        self.isoDate ?? self.getDate(dateFormatter: DateFormatters.backupISOFormatter, isoFormatter: DateFormatters.isoFormatter)
    }

    /// For multi-session events (F1), returns the last session's date (e.g. Race day)
    /// so the event appears under the correct day. Falls back to standardDate.
    var effectiveEndDate: Date? {
        if let sessions = sessions, !sessions.isEmpty,
           let lastDateStr = sessions.last?.date,
           let lastDate = DateFormatters.isoFormatter.date(from: lastDateStr) {
            return lastDate
        }
        return standardDate
    }

    /// All dates this event spans (for multi-session events like F1 weekends).
    /// Returns each unique calendar day from the first to last session.
    var sessionDates: [Date] {
        guard let sessions = sessions, !sessions.isEmpty else {
            return [standardDate].compactMap { $0 }
        }
        return sessions.compactMap { session in
            guard let dateStr = session.date else { return nil }
            return DateFormatters.isoFormatter.date(from: dateStr)
        }
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
                guard let dateStr = session.date,
                      let date = DateFormatters.isoFormatter.date(from: dateStr),
                      date > now else { return nil }
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
        if let next = nextUpcomingSession,
           let dateStr = next.date,
           let date = DateFormatters.isoFormatter.date(from: dateStr) {
            return .upcoming(label: sessionDisplayName(next.sessionType), date: date)
        }
        return .none
    }
}
