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

/// Maps each league to the sources that race for it. ESPN covers every fast-path league;
/// extra sources come from the environment so adding a provider — including a paid
/// one — is a config change, not a code change. Every source is polled each tick and
/// LiveMerge keeps whichever copy of a game is furthest along (`LiveMerge.shouldAccept`).
struct LiveSourceResolver {
    let espn: ESPNLiveSource
    /// Extra sources per league, raced against ESPN.
    let overrides: [Leagues: any LiveSource]

    func sources(for league: Leagues) -> [any LiveSource] {
        var sources: [any LiveSource] = []
        if league.liveBucket != nil { sources.append(espn) }
        if let extra = overrides[league] { sources.append(extra) }
        return sources
    }

    /// Group leagues by source so each source is hit once per tick.
    func groups(for leagues: Set<Leagues>) -> [(source: any LiveSource, leagues: Set<Leagues>)] {
        var bySource: [String: (any LiveSource, Set<Leagues>)] = [:]
        for league in leagues {
            for s in sources(for: league) {
                var entry = bySource[s.name] ?? (s, Set<Leagues>())
                entry.1.insert(league)
                bySource[s.name] = entry
            }
        }
        // ESPN first: it's the snapshot's own upstream, so the extra sources race against
        // what it just wrote rather than the other way round.
        func rank(_ name: String) -> Int { name == "espn" ? 0 : 1 }
        return bySource.values
            .map { (source: $0.0, leagues: $0.1) }
            .sorted { a, b in
                let (ra, rb) = (rank(a.source.name), rank(b.source.name))
                return ra != rb ? ra < rb : a.source.name < b.source.name
            }
    }

    /// Source names configured per league, for the admin dashboard.
    func describe() -> [String: [String]] {
        var out: [String: [String]] = [:]
        for (league, source) in overrides { out["\(league)", default: ["espn"]].append(source.name) }
        return out
    }

    /// Build from the environment. Each `LIVE_SOURCE_*` var adds a source that races ESPN
    /// for that league; unset leaves the league on ESPN alone. New providers (incl. paid)
    /// slot in here — the commented line shows the one-line shape.
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

extension Leagues {
    /// The snapshot bucket this league's games live in on the fast path, or nil when the
    /// league isn't fast-polled from ESPN (golf and tennis have their own jobs; motorsport
    /// is rebuilt whole by its series services).
    var liveBucket: SportType? {
        if isSoccer { return .soccer }
        if isFootball { return .nfl }
        if isBasketball { return .basketball }
        switch self {
        case .nhl: return .hockey
        case .mlb: return .mlb
        default: return nil
        }
    }
}
