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
        /// Outs and runners, down and distance, win probability. Optional: pushes from
        /// a server that predates it, and activities started before it, decode fine.
        var situation: LiveActivitySituation? = nil
        /// F1: session + top three. Optional for the same reasons as `situation`.
        var race: LiveActivityRace? = nil

        /// The state for `game` as the app sees it. Mirrors the server's APNS state so a
        /// foreground update and a push agree (and the state diff doesn't flap).
        static func make(for game: SportsCalModel.Game, standings: F1Standings?) -> ContentState {
            ContentState(
                homeScore: Int(game.intHomeScore ?? "") ?? 0,
                awayScore: Int(game.intAwayScore ?? "") ?? 0,
                status: game.strStatus,
                progress: game.strProgress,
                lastPlay: nil,
                situation: LiveActivitySituation(game.situation),
                race: game.isRace ? LiveActivityRace(game: game, standings: standings) : nil
            )
        }
    }

    /// `awayTeam` for F1 activities. Attributes are fixed at start, and F1's strAwayTeam
    /// is whoever leads at that moment, so a constant label stands in. Matches the
    /// server's `ESPNFetchJob.raceActivitySubtitle`.
    static let raceSubtitle = "Formula 1"

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
