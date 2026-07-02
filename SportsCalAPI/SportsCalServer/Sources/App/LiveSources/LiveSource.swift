//
//  LiveSource.swift
//
//  Pluggable live-score sources for the fast LiveTicker path. Each league can be
//  backed by a different upstream (ESPN today, FIFA's official feed for the World
//  Cup, a paid provider tomorrow) without touching the ticker or the merge logic.
//
//  Adding a paid provider is intentionally a one-liner: implement `LiveSource`,
//  then route a league to it in `LiveSourceResolver.fromEnvironment()`.
//

import Foundation
import Vapor
import SportsCalModel

protocol LiveSource: Sendable {
    /// Stable identifier used for grouping/logging (e.g. "espn", "fifa").
    var name: String { get }
    /// Which snapshot bucket this source's games overlay (see LiveMerge.overlay).
    var sport: SportType { get }
    /// How this source's games are matched into the snapshot (see LiveMerge.MatchStrategy).
    var matchStrategy: LiveMerge.MatchStrategy { get }
    /// Fetch fresh games for currently in-progress events in `leagues`. Returns the
    /// live/just-ended games; upcoming games may be omitted (the ticker only overlays
    /// onto in-progress snapshot games).
    func fetchLive(leagues: Set<Leagues>, app: Application) async throws -> [Game]
}

/// Maps each league to its configured `LiveSource`. Default: everything ESPN.
/// Overrides come from the environment so flipping a league to a new provider —
/// including a paid one — is a config change, not a code change.
struct LiveSourceResolver {
    let espn: ESPNLiveSource
    let overrides: [Leagues: any LiveSource]

    func source(for league: Leagues) -> any LiveSource {
        overrides[league] ?? espn
    }

    /// Group leagues by their resolved source so each source is hit once per tick.
    func groups(for leagues: Set<Leagues>) -> [(source: any LiveSource, leagues: Set<Leagues>)] {
        var bySource: [String: (any LiveSource, Set<Leagues>)] = [:]
        for league in leagues {
            let s = source(for: league)
            var entry = bySource[s.name] ?? (s, Set<Leagues>())
            entry.1.insert(league)
            bySource[s.name] = entry
        }
        return bySource.values.map { (source: $0.0, leagues: $0.1) }
    }

    /// Build from the environment. Each `LIVE_SOURCE_*` var routes a league to a
    /// non-default source; unset leaves it on ESPN. New providers (incl. paid) slot in
    /// here — the commented line shows the one-line shape.
    static func fromEnvironment() -> LiveSourceResolver {
        var overrides: [Leagues: any LiveSource] = [:]

        // World Cup — FIFA official feed (free). Paid drop-in would be one more case.
        switch Environment.get("LIVE_SOURCE_WORLDCUP")?.lowercased() {
        case "fifa": overrides[.FIFA_World_Cup] = FIFALiveSource()
        // case "apifootball": overrides[.FIFA_World_Cup] = APIFootballLiveSource()
        default: break
        }

        // MLB — official statsapi (free).
        switch Environment.get("LIVE_SOURCE_MLB")?.lowercased() {
        case "statsapi", "mlb": overrides[.mlb] = MLBLiveSource()
        default: break
        }

        // NHL — official api-web (free). In-season verification pending.
        switch Environment.get("LIVE_SOURCE_NHL")?.lowercased() {
        case "nhle", "nhl": overrides[.nhl] = NHLLiveSource()
        default: break
        }

        // NBA — official cdn.nba.com (free). In-season verification pending.
        switch Environment.get("LIVE_SOURCE_NBA")?.lowercased() {
        case "cdn", "nba": overrides[.nba] = NBALiveSource()
        default: break
        }

        return LiveSourceResolver(espn: ESPNLiveSource(), overrides: overrides)
    }
}
