//
//  LiveSportActivityAttributes.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/28/22.
//

import Foundation
import ActivityKit
import SportsCalModel

struct LiveSportActivityAttributes: ActivityAttributes {
    typealias Game = ContentState
    
    public struct ContentState: Codable, Hashable {
        var homeScore: Int
        var awayScore: Int
        var status: String?
        var progress: String?
    }
    
    var homeTeam: String
    var awayTeam: String
    var homeID: String?
    var awayID: String?
    var eventID: String
    var league: String?
    var awayURL: String?
    var homeURL: String?
}