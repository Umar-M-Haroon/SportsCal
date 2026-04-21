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
