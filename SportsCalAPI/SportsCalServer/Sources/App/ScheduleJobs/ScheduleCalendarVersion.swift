//
//  ScheduleCalendarVersion.swift
//
//  What a client's cached schedule actually depends on, hashed per sport.
//
//  The schedule blob changes every minute while anything is live: ESPNFetchJob folds
//  each tick's clock, last play, situation and leaders into it. The `/schedules` ETag
//  used to be a hash of the whole blob, so every one of those ticks invalidated every
//  client's copy and the next app open re-downloaded the full payload (measured
//  2026-10-04: 28MB of JSON re-sent for changes to 2–3 games, almost every minute).
//
//  Clients don't need those ticks from `/schedules`: the live socket delivers them and
//  the app merges them into its copy (`GameViewModel.mergeLiveIntoSchedule`). So the
//  ETag is built from a projection that leaves them out:
//
//  - every game: identity, teams, kickoff, venue, round, season, enrichment presence;
//  - scheduled and in-progress games count as one state ("open"), so neither kickoff
//    nor any in-game change moves the version;
//  - called-off games (postponed, cancelled, suspended) keep their status;
//  - finished games add the final score and status: the server prunes finished games
//    from the live snapshot, so the schedule is where a final result has to come from.
//
//  The full body is still served on every 200, so a fresh fetch is always current.
//

import Foundation
import Crypto
import SportsCalModel

enum ScheduleCalendarVersion {
    /// One version per wire bucket ("nba", "nfl", "ncaaf", "racing", "motorsport", …)
    /// plus "meta" for the top-level enrichment (F1 standings, World Cup).
    static func versions(of schedule: LiveScore) -> [String: String] {
        var result: [String: String] = [:]
        for (key, games) in wireBuckets(of: schedule) {
            result[key] = hash(games.map(projection))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let meta = [
            schedule.f1Standings.flatMap { try? encoder.encode($0) },
            schedule.worldCup.flatMap { try? encoder.encode($0) },
        ].map { $0.map { String(decoding: $0, as: UTF8.self) } ?? "-" }
        result["meta"] = hash(meta)
        return result
    }

    /// The whole schedule's version: every bucket's, in a fixed order.
    static func combined(_ versions: [String: String]) -> String {
        hash(versions.keys.sorted().map { "\($0)=\(versions[$0]!)" })
    }

    /// Games per key as they travel on the wire: college football apart from the NFL
    /// and racing series beyond F1 apart from F1 (see `LiveScore`'s Codable).
    static func wireBuckets(of schedule: LiveScore) -> [(key: String, games: [Game])] {
        var buckets: [(String, [Game])] = []
        for (sport, keyPath) in LiveScore.sportKeyPaths {
            guard let games = schedule[keyPath: keyPath]?.events else { continue }
            switch sport {
            case .nfl:
                buckets.append(("nfl", games.filter { !$0.isCollegeFootball }))
                buckets.append(("ncaaf", games.filter(\.isCollegeFootball)))
            case .racing:
                buckets.append(("racing", games.filter { !$0.isMotorsportSeries }))
                buckets.append(("motorsport", games.filter(\.isMotorsportSeries)))
            default:
                buckets.append((wireKey(for: sport), games))
            }
        }
        return buckets
    }

    static func wireKey(for sport: SportType) -> String {
        switch sport {
        case .basketball: "nba"
        case .mlb: "mlb"
        case .soccer: "soccer"
        case .nfl: "nfl"
        case .hockey: "nhl"
        case .golf: "golf"
        case .tennis: "tennis"
        case .racing: "racing"
        }
    }

    // MARK: - Projection

    /// The fields of `game` a cached copy depends on, as one line.
    static func projection(_ game: Game) -> String {
        var parts: [String] = [
            game.idEvent ?? "", game.idLeague ?? "",
            game.strHomeTeam, game.strAwayTeam, game.idHomeTeam ?? "", game.idAwayTeam ?? "",
            game.strHomeTeamBadge ?? "", game.strAwayTeamBadge ?? "",
            game.strTimestamp ?? "", game.endDate ?? "", game.venueName ?? "",
            game.round ?? "", game.tournamentName ?? "", game.drawSlug ?? "",
            game.season ?? "", game.seasonPhase?.rawValue ?? "",
            game.homeSeed.map(String.init) ?? "", game.awaySeed.map(String.init) ?? "",
            game.homeConference ?? "", game.awayConference ?? "",
            game.homeRecord ?? "", game.awayRecord ?? "",
            game.playoff?.seriesTitle ?? "", game.playoff?.gameNumber.map(String.init) ?? "",
            // Enrichment the hourly jobs attach: presence and size, not every detail.
            "\(game.homeInjuries?.count ?? -1)/\(game.awayInjuries?.count ?? -1)",
            game.circuitInfo?.circuitImageURL ?? (game.circuitInfo == nil ? "" : "c"),
            game.golfCourseInfo == nil ? "" : "g",
            game.raceTiming == nil ? "" : "t",
        ]
        // Race weekends: each session's slot and, once it's done, who won it.
        for session in game.sessions ?? [] {
            let done = session.status == "post"
            parts.append("\(session.sessionType)@\(session.date ?? "")\(done ? "=" + (session.leaderboard.first?.name ?? "") : "")")
        }
        switch state(of: game) {
        case .open:
            parts.append("open")
        case .calledOff(let status):
            parts.append("off:\(status)")
        case .final:
            parts.append(contentsOf: [
                "final", game.strStatus ?? "", game.strProgress ?? "",
                game.intHomeScore ?? "", game.intAwayScore ?? "",
                (game.homeLinescores ?? []).map { String($0) }.joined(separator: ","),
                (game.awayLinescores ?? []).map { String($0) }.joined(separator: ","),
                game.leaderboardEntries?.first.map { "\($0.name):\($0.score)" } ?? "",
                game.excitement.map(String.init) ?? "",
            ])
        }
        return parts.joined(separator: "\u{1F}")
    }

    enum State: Equatable {
        case open, final, calledOff(String)
    }

    static func state(of game: Game) -> State {
        let status = game.strStatus ?? ""
        let lowered = status.lowercased()
        if ["postpon", "cancel", "abandon", "suspend", "ppd", "canc", "delay"].contains(where: lowered.contains) {
            return .calledOff(status)
        }
        if game.isCompleted == true { return .final }
        if finalStatuses.contains(status) { return .final }
        if let progress = game.strProgress, progress.hasPrefix("Final") || progress == "FT" { return .final }
        return .open
    }

    private static let finalStatuses: Set<String> = [
        "post", "FT", "AOT", "AET", "PEN", "AP", "Final", "Final/OT", "Match Finished",
    ]

    // MARK: - Hash

    static func hash(_ lines: [String]) -> String {
        var hasher = SHA256()
        for line in lines {
            hasher.update(data: Data(line.utf8))
            hasher.update(data: Data([0x0A]))
        }
        return hasher.finalize().prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
