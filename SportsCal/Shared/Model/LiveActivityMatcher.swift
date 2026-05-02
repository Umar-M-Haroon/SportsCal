//
//  LiveActivityMatcher.swift
//  Scoreline
//
//  Pure matching logic extracted from GameViewModel.updateLiveActivities so
//  the eventID-first / team-name-fallback resolution can be exercised by unit
//  tests without depending on ActivityKit. The actual call into
//  `Activity.update(using:)` stays in GameViewModel.
//

import Foundation
#if canImport(ActivityKit) && os(iOS)
import SportsCalModel

enum LiveActivityMatcher {
    struct StateLookup: Equatable {
        var byEventID: [String: LiveSportActivityAttributes.ContentState]
        /// Keyed by `"<home>|<away>"`, both lowercased — fuzzy fallback for when
        /// TheSportsDB and ESPN disagree on event IDs but the teams still line up.
        var byTeams: [String: LiveSportActivityAttributes.ContentState]
    }

    /// Build the lookup from live event games. A game without `idEvent` still
    /// gets a team-key entry so the fallback path can match it.
    static func buildLookup(from liveEvents: [Game]) -> StateLookup {
        var byEventID: [String: LiveSportActivityAttributes.ContentState] = [:]
        var byTeams: [String: LiveSportActivityAttributes.ContentState] = [:]
        for game in liveEvents {
            let state = LiveSportActivityAttributes.ContentState(
                homeScore: Int(game.intHomeScore ?? "") ?? 0,
                awayScore: Int(game.intAwayScore ?? "") ?? 0,
                status: game.strStatus,
                progress: game.strProgress,
                lastPlay: nil
            )
            if let eventID = game.idEvent {
                byEventID[eventID] = state
            }
            let teamKey = teamKey(home: game.strHomeTeam, away: game.strAwayTeam)
            byTeams[teamKey] = state
        }
        return StateLookup(byEventID: byEventID, byTeams: byTeams)
    }

    /// Resolve a state for an activity: try eventID first, then team-name fallback.
    static func matchedState(
        eventID: String,
        homeTeam: String,
        awayTeam: String,
        in lookup: StateLookup
    ) -> LiveSportActivityAttributes.ContentState? {
        if let state = lookup.byEventID[eventID] { return state }
        return lookup.byTeams[teamKey(home: homeTeam, away: awayTeam)]
    }

    /// Returns the new state to write — or nil if no match exists, or the matched
    /// state is identical to what's already on the activity (avoids redundant
    /// `Activity.update` calls that show up as a "received update" telemetry blip
    /// on the device).
    static func resolveUpdate(
        eventID: String,
        homeTeam: String,
        awayTeam: String,
        currentState: LiveSportActivityAttributes.ContentState,
        in lookup: StateLookup
    ) -> LiveSportActivityAttributes.ContentState? {
        guard let newState = matchedState(eventID: eventID, homeTeam: homeTeam, awayTeam: awayTeam, in: lookup) else {
            return nil
        }
        return newState != currentState ? newState : nil
    }

    static func teamKey(home: String, away: String) -> String {
        "\(home.lowercased())|\(away.lowercased())"
    }
}
#endif
