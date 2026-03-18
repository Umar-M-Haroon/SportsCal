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
}
