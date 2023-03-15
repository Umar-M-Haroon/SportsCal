//
//  Teams+Extensions.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/24/22.
//

import Foundation
import SportsCalModel

extension Team {
    @available(*, deprecated, message: "use Dictionary lookup")
    static func getTeamInfoFrom(teams: [Team], teamID: String?) -> Team? {
        return teams.first { team in
            team.idTeam == teamID
        }
    }
    static func getTeamInfoFrom(teamDict: [String?: [Team]], teamID: String?) -> Team? {
        return teamDict[teamID]?.first
    }
    
    static func getTeamInfoFrom(teams: [Team], teamName: String?) -> Team? {
        return teams.first { team in
            team.strTeam == teamName
        }
    }
}

extension Game {
    var isoDate: Date? {
        self.getDate(dateFormatter: DateFormatters.backupISOFormatter, isoFormatter: DateFormatters.isoFormatter)
    }
}
