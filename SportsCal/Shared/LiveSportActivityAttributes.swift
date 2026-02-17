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
}
#endif
