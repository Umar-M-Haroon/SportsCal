//
//  LiveMerge.swift
//
//  Surgical, pure merge helpers used by the fast LiveTicker path. Kept free of
//  Redis / Vapor so they're unit-testable without booting the app.
//

import Foundation
import SportsCalModel

enum LiveMerge {
    /// How a fresh game from a source is matched to a game already in the snapshot.
    enum MatchStrategy {
        /// The fresh game shares the snapshot's `idEvent` (same upstream, e.g. ESPN).
        case eventID
        /// Cross-source: match by team names + kickoff day (FIFA / paid providers,
        /// whose IDs live in a different namespace than the ESPN-sourced snapshot).
        case teamsAndDay
    }

    /// Result of a fast-path overlay: the updated snapshot plus the set of snapshot
    /// event IDs whose score or status changed this pass (gates the fast goal-push so
    /// the install scan only runs on real goals, not every tick).
    struct Result: Equatable {
        let liveScore: LiveScore
        let changedEventIDs: Set<String>
    }

    /// Back-compat entry point — same-source (ESPN) soccer overlay matched by `idEvent`.
    static func overlaySoccerInProgress(cached: LiveScore, fresh: [Game]) -> Result {
        overlaySoccer(cached: cached, fresh: fresh, strategy: .eventID)
    }

    /// Convenience for the soccer bucket.
    static func overlaySoccer(cached: LiveScore, fresh: [Game], strategy: MatchStrategy) -> Result {
        overlay(cached: cached, sport: .soccer, fresh: fresh, strategy: strategy)
    }

    /// Overlays fresh in-progress scores onto one sport bucket of the cached snapshot WITHOUT
    /// adding, removing, or reordering games.
    ///
    /// Only games already in that bucket with status `"in"` are eligible. A fresh copy is
    /// matched per `strategy`, and its score/status/clock/lastPlay fields are overlaid onto
    /// the *cached* game via `Game.updated`, so the cached game's TSDB-translated team IDs and
    /// identity (incl. the snapshot's own `idEvent`) survive untouched. Every other bucket and
    /// every upcoming game pass through verbatim — per-game play-by-play lives in separate
    /// `PBP-*` keys, so it's structurally safe.
    static func overlay(cached: LiveScore, sport: SportType, fresh: [Game], strategy: MatchStrategy) -> Result {
        guard let bucket = events(in: cached, sport: sport) else {
            return Result(liveScore: cached, changedEventIDs: [])
        }
        let (merged, changed) = overlayEvents(bucket, fresh: fresh, strategy: strategy)
        return Result(liveScore: replacing(cached, sport: sport, with: merged), changedEventIDs: changed)
    }

    /// Core overlay over a single bucket's events. Returns the merged events and the set of
    /// snapshot `idEvent`s whose score/status changed.
    static func overlayEvents(_ events: [Game], fresh: [Game], strategy: MatchStrategy) -> (events: [Game], changed: Set<String>) {
        let freshByKey = Dictionary(
            fresh.compactMap { game in matchKey(for: game, strategy: strategy).map { ($0, game) } },
            uniquingKeysWith: { _, new in new }
        )

        var changed = Set<String>()
        let merged: [Game] = events.map { game in
            guard game.strStatus == "in",
                  let key = matchKey(for: game, strategy: strategy),
                  let f = freshByKey[key] else { return game }

            let scoreChanged = f.intHomeScore != game.intHomeScore
                || f.intAwayScore != game.intAwayScore
                || f.strStatus != game.strStatus
            if scoreChanged, let id = game.idEvent { changed.insert(id) }

            return game.updated(
                intHomeScore: f.intHomeScore,
                intAwayScore: f.intAwayScore,
                strStatus: f.strStatus,
                strProgress: f.strProgress,
                lastPlay: f.lastPlay,
                homeLinescores: f.homeLinescores,
                awayLinescores: f.awayLinescores,
                homeLeaders: f.homeLeaders,
                awayLeaders: f.awayLeaders,
                isCompleted: f.isCompleted,
                aggregateScore: f.aggregateScore
            )
        }
        return (merged, changed)
    }

    // MARK: - Bucket access by sport

    private static func events(in s: LiveScore, sport: SportType) -> [Game]? {
        switch sport {
        case .basketball: return s.nba?.events
        case .soccer:     return s.soccer?.events
        case .hockey:     return s.nhl?.events
        case .mlb:        return s.mlb?.events
        case .nfl:        return s.nfl?.events
        case .golf:       return s.golf?.events
        case .tennis:     return s.tennis?.events
        case .racing:     return s.racing?.events
        }
    }

    private static func replacing(_ s: LiveScore, sport: SportType, with events: [Game]) -> LiveScore {
        let e = LiveEvent(events: events)
        return LiveScore(
            nba:    sport == .basketball ? e : s.nba,
            mlb:    sport == .mlb        ? e : s.mlb,
            soccer: sport == .soccer     ? e : s.soccer,
            nfl:    sport == .nfl        ? e : s.nfl,
            nhl:    sport == .hockey     ? e : s.nhl,
            golf:   sport == .golf       ? e : s.golf,
            tennis: sport == .tennis     ? e : s.tennis,
            racing: sport == .racing     ? e : s.racing
        )
    }

    // MARK: - Matching

    static func matchKey(for game: Game, strategy: MatchStrategy) -> String? {
        switch strategy {
        case .eventID:
            return game.idEvent
        case .teamsAndDay:
            guard let day = dayString(for: game) else { return nil }
            let home = canonicalTeam(game.strHomeTeam)
            let away = canonicalTeam(game.strAwayTeam)
            guard !home.isEmpty, !away.isEmpty else { return nil }
            return "\(day)|\(home)|\(away)"
        }
    }

    /// "YYYY-MM-DD" UTC day for a game, from isoDate or the strTimestamp prefix.
    static func dayString(for game: Game) -> String? {
        if let date = game.isoDate {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(secondsFromGMT: 0)
            return df.string(from: date)
        }
        if let ts = game.strTimestamp, ts.count >= 10 {
            return String(ts.prefix(10))
        }
        return nil
    }

    /// Canonicalizes a national-team name so the same country matches across ESPN and FIFA
    /// naming. Lowercase + strip diacritics/punctuation, then map known World Cup variants.
    /// Unmatched names just normalize to lowercase — exact matches still work; the alias map
    /// is a safety net for the handful of countries the two feeds spell differently.
    static func canonicalTeam(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return countryAliases[folded] ?? folded
    }

    /// ESPN/FIFA spelling variants → a shared canonical form. Extend as unmatched live
    /// games are logged during the tournament.
    private static let countryAliases: [String: String] = [
        "usa": "united states",
        "us": "united states",
        "korea republic": "south korea",
        "republic of korea": "south korea",
        "korea dpr": "north korea",
        "ivory coast": "cote divoire",
        "côte d'ivoire": "cote divoire",
        "cote d ivoire": "cote divoire",
        "czechia": "czech republic",
        "cabo verde": "cape verde",
        "dr congo": "congo dr",
        "congo dr": "congo dr",
        "democratic republic of the congo": "congo dr",
        "türkiye": "turkey",
        "turkiye": "turkey",
        "china pr": "china",
    ]
}
