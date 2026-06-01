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

/// Pure decision helper for the dedup funnel — given the eventIDs of currently
/// active Live Activities, decides whether the caller should request a new one
/// or update an existing one. Extracted from `GameViewModel.requestActivity` so
/// the logic is unit-testable without ActivityKit.
///
/// The funnel matters: iOS ActivityKit happily spawns two activities for the
/// same attributes. The bug we're fixing is "same game shows twice" — every
/// caller must route through this planner before touching `Activity.request`.
enum LiveActivityRequestPlan: Equatable {
    case createNew
    case updateExisting
}

enum LiveActivityRequestPlanner {
    static func plan(existingEventIDs: [String], for eventID: String) -> LiveActivityRequestPlan {
        existingEventIDs.contains(eventID) ? .updateExisting : .createNew
    }
}
#endif
