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
        return teams.first { team in
            team.idTeam == teamID
        }
    }
}

extension Game {
    var isoDate: Date? {
        self.getDate(dateFormatter: DateFormatters.backupISOFormatter, isoFormatter: DateFormatters.isoFormatter)
    }
}
