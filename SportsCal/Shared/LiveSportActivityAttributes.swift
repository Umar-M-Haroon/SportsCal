//
//  LiveSportActivityAttributes.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/28/22.
//

import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import SportsCalModel

struct LiveSportActivityAttributes: ActivityAttributes {
    typealias Game = ContentState

    public struct ContentState: Codable, Hashable {
        var homeScore: Int
        var awayScore: Int
        var status: String?
        var progress: String?
        var lastPlay: String? // e.g., "Durant hits 3-pointer" or "Goal by Messi (45')"
    }

    var homeTeam: String
    var awayTeam: String
    var eventID: String
    /// League-style short abbreviations (e.g. "PHI", "BOS", "NYY"). Optional for
    /// backward compat with activities started before the field existed. The
    /// Dynamic Island compact and minimal slots use these because raster team
    /// logos get tinted to silhouettes there. Nil → widget falls back to first
    /// 3 chars of the full name.
    var homeTeamShort: String? = nil
    var awayTeamShort: String? = nil
}
#endif
