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
        /// Games whose live situation (count, runners, down and distance) moved without a
        /// score change. Worth publishing to the socket, not worth a push scan.
        var situationChangedEventIDs: Set<String> = []
        /// Every in-progress snapshot game this source had a copy of, keyed by snapshot
        /// `idEvent`, with the source's score key ("away-home"). Feeds LiveSourceStats,
        /// which needs what each source *saw*, not just what it won.
        var observedScores: [String: String] = [:]
        /// Snapshot games where this source's copy was behind the snapshot and was dropped.
        var behindEventIDs: Set<String> = []
    }

    /// How the fast path treats a source's copy when several sources race for one game.
    struct RaceOptions {
        /// The source the fresh games came from (LiveSource.name).
        var source: String
        /// Snapshot `idEvent` → the only source allowed to write that game (admin override).
        var forcedSources: [String: String] = [:]
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
    ///
    /// With `race`, the overlay is one of several sources for the bucket: a copy that is
    /// behind the snapshot (see `shouldAccept`) is dropped instead of rolling the game back,
    /// and a game pinned to another source by an admin override is left alone.
    static func overlay(
        cached: LiveScore,
        sport: SportType,
        fresh: [Game],
        strategy: MatchStrategy,
        race: RaceOptions? = nil
    ) -> Result {
        guard let bucket = events(in: cached, sport: sport) else {
            return Result(liveScore: cached, changedEventIDs: [])
        }
        let pass = overlayEventsDetailed(bucket, fresh: fresh, strategy: strategy, race: race)
        let (merged, changed) = (pass.events, pass.changed)
        // The overlay never adds, drops or reorders games, so old and new line up by index.
        var situationChanged = Set<String>()
        for (old, new) in zip(bucket, merged) where old.situation != new.situation {
            if let id = new.idEvent, !changed.contains(id) { situationChanged.insert(id) }
        }
        return Result(
            liveScore: replacing(cached, sport: sport, with: merged),
            changedEventIDs: changed,
            situationChangedEventIDs: situationChanged,
            observedScores: pass.observed,
            behindEventIDs: pass.behind
        )
    }

    /// Core overlay over a single bucket's events. Returns the merged events and the set of
    /// snapshot `idEvent`s whose score/status changed.
    static func overlayEvents(_ events: [Game], fresh: [Game], strategy: MatchStrategy) -> (events: [Game], changed: Set<String>) {
        let pass = overlayEventsDetailed(events, fresh: fresh, strategy: strategy, race: nil)
        return (pass.events, pass.changed)
    }

    private struct OverlayPass {
        var events: [Game]
        var changed: Set<String>
        var observed: [String: String]
        var behind: Set<String>
    }

    private static func overlayEventsDetailed(
        _ events: [Game],
        fresh: [Game],
        strategy: MatchStrategy,
        race: RaceOptions?
    ) -> OverlayPass {
        // Several fresh games can share a teams+day key — a doubleheader — so keep them
        // all and pick per snapshot game (see `bestMatch`).
        var freshByKey: [String: [Game]] = [:]
        for game in fresh {
            guard let key = matchKey(for: game, strategy: strategy) else { continue }
            freshByKey[key, default: []].append(game)
        }

        var changed = Set<String>()
        var observed: [String: String] = [:]
        var behind = Set<String>()
        // The ESPN source (and the same-upstream `.eventID` overlay, which is ESPN) sends
        // a complete situation; every other source only part of one.
        let freshSituationIsComplete = race.map { $0.source == ESPNLiveSource.sourceName }
            ?? (strategy == .eventID)
        let merged: [Game] = events.map { game in
            guard game.strStatus == "in",
                  let key = matchKey(for: game, strategy: strategy),
                  let f = bestMatch(for: game, among: freshByKey[key] ?? []) else { return game }

            if let race, let id = game.idEvent {
                observed[id] = scoreKey(f)
                if let pinned = race.forcedSources[id] {
                    // Pinned: the named source writes unconditionally, every other one is ignored.
                    guard pinned == race.source else { return game }
                } else if !shouldAccept(f, over: game) {
                    behind.insert(id)
                    return game
                }
            }

            let scoreChanged = f.intHomeScore != game.intHomeScore
                || f.intAwayScore != game.intAwayScore
                || f.strStatus != game.strStatus
            if scoreChanged, let id = game.idEvent { changed.insert(id) }

            var merged = game.updated(
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
                aggregateScore: f.aggregateScore,
                // Only ESPN sends the whole set (R/H/E, pitchers, TV); a partial source's
                // (statsapi's doubleheader number) must not replace it. nil keeps the
                // snapshot's.
                scoreboardExtras: freshSituationIsComplete ? f.scoreboardExtras : nil
            )
            // ESPN's situation is the whole picture, so it replaces the old one outright:
            // a nil down, distance, red zone or possession means "none right now" (a
            // touchdown, halftime, the break between quarters), and overlaying would keep
            // the stale one. A partial source (MLB statsapi) updates the fields it has and
            // keeps the rest of ESPN's — game lines, win probability. One without keeps
            // ESPN's from the last full fetch, minus the clock if the score just moved:
            // that clock predates the basket, and the clutch rules read it.
            if let fresh = f.situation {
                if freshSituationIsComplete {
                    merged.situation = fresh
                } else {
                    merged.situation = game.situation.map { $0.overlaying(fresh) } ?? fresh
                }
            } else if scoreChanged {
                merged.situation?.clock = nil
            }
            // A game that just ended must not keep claiming two on and two out.
            if f.strStatus != "in" { merged.situation = nil }
            return merged
        }
        return OverlayPass(events: merged, changed: changed, observed: observed, behind: behind)
    }

    // MARK: - Racing sources

    /// "away-home" — the score as a source reported it, for cross-source comparison.
    static func scoreKey(_ game: Game) -> String {
        "\(game.intAwayScore ?? "-")-\(game.intHomeScore ?? "-")"
    }

    /// How far along a game is, as far as its live situation says: period, then the phase
    /// inside it (baseball's half inning), then elapsed time within the period. nil when
    /// the source gave no period.
    struct GameProgress: Equatable {
        var period: Int
        var phase: Int
        /// nil when the clock is unknown — the overlay clears a stale clock when the score
        /// moves — so it must not read as the end of the period.
        var elapsed: Double?

        init(period: Int, phase: Int = 0, elapsed: Double?) {
            self.period = period
            self.phase = phase
            self.elapsed = elapsed
        }

        init?(_ game: Game) {
            guard let situation = game.situation, let period = situation.period else { return nil }
            self.period = period
            let league = game.idLeague.flatMap { Int($0) }.flatMap(Leagues.init(rawValue:))
            if league == .mlb {
                switch situation.inningHalf {
                case .top: phase = 0
                case .middle: phase = 1
                case .bottom: phase = 2
                case .end: phase = 3
                case nil: phase = 0
                }
                elapsed = Double(situation.outs ?? 0)
            } else {
                phase = 0
                // Soccer's clock counts up; basketball, football and hockey count down.
                elapsed = situation.clock.map { league?.isSoccer == true ? $0 : -$0 }
            }
        }

        /// -1, 0 or 1. Elapsed time only breaks a period/phase tie when both sides know it.
        static func order(_ a: GameProgress, _ b: GameProgress) -> Int {
            if a.period != b.period { return a.period < b.period ? -1 : 1 }
            if a.phase != b.phase { return a.phase < b.phase ? -1 : 1 }
            guard let ea = a.elapsed, let eb = b.elapsed, ea != eb else { return 0 }
            return ea < eb ? -1 : 1
        }
    }

    /// Whether a source's fresh copy should replace the snapshot's when several sources
    /// race for the same game. The rule is "never go backwards in game time":
    ///
    /// - A later status wins outright and an earlier one loses (pre < in < post).
    /// - When both copies carry a period, game progress decides. A copy from later in the
    ///   game wins even with a lower score — that's a scoring correction, and it must get
    ///   through. At the same moment, the higher (or equal) total wins.
    /// - Without progress on both sides, only a strictly higher total wins, unless the
    ///   snapshot has no progress of its own to protect (a game only that source covers).
    static func shouldAccept(_ fresh: Game, over current: Game) -> Bool {
        let (rf, rc) = (statusRank(fresh), statusRank(current))
        if rf != rc { return rf > rc }
        let (tf, tc) = (totalScore(fresh), totalScore(current))
        if let pf = GameProgress(fresh), let pc = GameProgress(current) {
            let order = GameProgress.order(pf, pc)
            if order != 0 { return order > 0 }
            return tf >= tc
        }
        if tf != tc { return tf > tc }
        return GameProgress(current) == nil
    }

    private static func statusRank(_ game: Game) -> Int {
        switch game.strStatus {
        case "post": return 2
        case "in": return 1
        default: return game.isCompleted == true ? 2 : 0
        }
    }

    private static func totalScore(_ game: Game) -> Int {
        (game.intHomeScore.flatMap { Int($0) } ?? 0) + (game.intAwayScore.flatMap { Int($0) } ?? 0)
    }

    // MARK: - Concurrent-writer reconciliation

    /// Reconciles a slow full rebuild (`ours`, ESPNFetchJob) with writes another job
    /// (LiveTicker) made to the same snapshot while the rebuild was running.
    ///
    /// `baseline` is the snapshot the rebuild started from; `current` is the snapshot
    /// re-read just before writing. Any game whose copy in `current` differs from
    /// `baseline` was updated concurrently; its live fields are overlaid onto `ours`
    /// unless ours is further along (a later status, or a higher total score) — so a
    /// score the ticker already published never goes backwards when the slower job
    /// writes. Games are matched by `idEvent`; nothing is added or removed.
    ///
    /// Returns the reconciled snapshot and the event IDs that took the concurrent copy.
    static func preservingConcurrentUpdates(
        ours: LiveScore,
        baseline: LiveScore?,
        current: LiveScore?
    ) -> (liveScore: LiveScore, preserved: Set<String>) {
        guard let current else { return (ours, []) }
        var baselineByID: [String: Game] = [:]
        for (_, games) in baseline?.allGamesBySport ?? [] {
            for game in games { if let id = game.idEvent { baselineByID[id] = game } }
        }
        var concurrent: [String: Game] = [:]
        for (_, games) in current.allGamesBySport {
            for game in games {
                guard let id = game.idEvent, baselineByID[id] != game else { continue }
                concurrent[id] = game
            }
        }
        guard !concurrent.isEmpty else { return (ours, []) }

        var result = ours
        var preserved = Set<String>()
        for (_, keyPath) in LiveScore.sportKeyPaths {
            guard let events = result[keyPath: keyPath]?.events else { continue }
            var touched = false
            let merged = events.map { game -> Game in
                guard let id = game.idEvent, let theirs = concurrent[id],
                      isAtLeastAsFarAlong(theirs, as: game) else { return game }
                touched = true
                preserved.insert(id)
                var updated = game.updated(
                    intHomeScore: theirs.intHomeScore,
                    intAwayScore: theirs.intAwayScore,
                    strStatus: theirs.strStatus,
                    strProgress: theirs.strProgress,
                    lastPlay: theirs.lastPlay,
                    homeLinescores: theirs.homeLinescores,
                    awayLinescores: theirs.awayLinescores,
                    homeLeaders: theirs.homeLeaders,
                    awayLeaders: theirs.awayLeaders,
                    isCompleted: theirs.isCompleted,
                    aggregateScore: theirs.aggregateScore
                )
                updated.situation = theirs.situation
                return updated
            }
            if touched { result[keyPath: keyPath] = LiveEvent(events: merged) }
        }
        return (result, preserved)
    }

    /// Whether `a` is at least as far along as `b`: a later status wins outright
    /// (pre < in < post); at equal status the higher total score wins; a tie goes to `a`
    /// (the concurrent write, which is at least as recent as the rebuild's cached copy).
    static func isAtLeastAsFarAlong(_ a: Game, as b: Game) -> Bool {
        let (ra, rb) = (statusRank(a), statusRank(b))
        if ra != rb { return ra > rb }
        return totalScore(a) >= totalScore(b)
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

    /// The fresh copy of `game` among those sharing its match key. One candidate is the
    /// common case. A doubleheader has two on the same day with the same teams: match
    /// the game number when both sides know it, else the nearest scheduled start —
    /// last-one-wins once pushed game 1's final score onto a live game 2.
    static func bestMatch(for game: Game, among candidates: [Game]) -> Game? {
        guard candidates.count > 1 else { return candidates.first }
        if let number = game.doubleheaderGame,
           let same = candidates.first(where: { $0.doubleheaderGame == number }) {
            return same
        }
        guard let kickoff = kickoffDate(game) else { return candidates.last }
        return candidates.min { a, b in
            let da = kickoffDate(a).map { abs($0.timeIntervalSince(kickoff)) } ?? .infinity
            let db = kickoffDate(b).map { abs($0.timeIntervalSince(kickoff)) } ?? .infinity
            return da < db
        }
    }

    private static func kickoffDate(_ game: Game) -> Date? {
        game.isoDate ?? game.strTimestamp.flatMap(DateParsers.parse)
    }

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
