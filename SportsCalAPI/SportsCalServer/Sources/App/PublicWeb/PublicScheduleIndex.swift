//
//  PublicScheduleIndex.swift
//
//  The schedule, indexed by team, league and event, for the public web pages and
//  calendar feeds. Built from the same in-process schedule snapshot `/schedules` serves
//  (`currentSchedule`), so these routes add no Redis reads of their own beyond that
//  shared 30s snapshot, and never call upstream.
//
//  Decoding the whole multi-MB blob per request is what this exists to avoid. It is
//  decoded per wire bucket (`nba`, `soccer`, `tennis`, …), and a bucket is re-decoded
//  only when its calendar version moves (a final score, a new fixture), or at most every
//  five minutes while its content keeps changing (live scores on the game pages).
//

import Foundation
import Vapor
import SportsCalModel

struct PublicTeam {
    let id: String
    let name: String
    let slug: String
    /// The league this team plays most of its games in, e.g. Premier League over FA Cup.
    let primaryLeagueID: String?
    /// Every game in the window, oldest first.
    let games: [Game]
}

struct PublicLeague {
    let id: String
    let name: String
    let slug: String
    let sport: SportType?
    /// Every game in the window, oldest first.
    let games: [Game]
    /// Teams with games in this league, by name.
    let teamIDs: [String]
}

struct PublicSchedule {
    /// Bumped on every rebuild; keys the rendered-page cache.
    let generation: Int
    let teams: [String: PublicTeam]
    let leagues: [String: PublicLeague]
    let games: [String: Game]

    static let empty = PublicSchedule(generation: 0, teams: [:], leagues: [:], games: [:])
}

actor PublicScheduleIndex {
    static let shared = PublicScheduleIndex()

    /// How far back the index keeps games: the feeds promise ~30 days of results.
    static let lookback: TimeInterval = 35 * 86_400
    /// How long a bucket may lag behind content-only changes (live scores).
    static let contentRefresh: TimeInterval = 300

    private struct Bucket {
        let stamp: String
        let sourceVersion: String
        let builtAt: Date
        let games: [Game]
    }

    private var buckets: [String: Bucket] = [:]
    private var built = PublicSchedule.empty
    private var checkedSourceVersion: String?
    private var generation = 0

    func current(source: String, version: String, calendar: [String: String]?, now: Date = Date()) -> PublicSchedule {
        if checkedSourceVersion == version, built.generation > 0 { return built }
        checkedSourceVersion = version

        var stale: [LiveScore.WireKey] = []
        for key in LiveScore.WireKey.allCases where key != .meta {
            let stamp = calendar?[key.rawValue] ?? version
            guard let bucket = buckets[key.rawValue] else {
                stale.append(key)
                continue
            }
            if bucket.stamp != stamp {
                stale.append(key)
            } else if bucket.sourceVersion != version, now.timeIntervalSince(bucket.builtAt) >= Self.contentRefresh {
                stale.append(key)
            }
        }
        if stale.isEmpty, built.generation > 0 { return built }

        let bytes = Array(source.utf8)
        let ranges = CollegePayload.topLevelValueRanges(in: bytes)
        let cutoff = now.addingTimeInterval(-Self.lookback)
        for key in stale {
            let stamp = calendar?[key.rawValue] ?? version
            let games = Self.decodeBucket(key, bytes: bytes, ranges: ranges, cutoff: cutoff)
            buckets[key.rawValue] = Bucket(stamp: stamp, sourceVersion: version, builtAt: now, games: games)
        }

        generation += 1
        var all: [Game] = []
        for key in LiveScore.WireKey.allCases {
            if let bucket = buckets[key.rawValue] { all.append(contentsOf: bucket.games) }
        }
        built = Self.index(all, generation: generation)
        return built
    }

    func reset() {
        buckets = [:]
        built = .empty
        checkedSourceVersion = nil
    }

    // MARK: - Building

    private static func decodeBucket(_ key: LiveScore.WireKey, bytes: [UInt8], ranges: [String: Range<Int>], cutoff: Date) -> [Game] {
        guard let range = ranges[key.rawValue] else { return [] }
        var json: [UInt8] = Array("{\"\(key.rawValue)\":".utf8)
        json.append(contentsOf: bytes[range])
        json.append(UInt8(ascii: "}"))
        guard let decoded = try? JSONDecoder().decode(LiveScore.self, from: Data(json)) else { return [] }
        var games: [Game] = []
        for (_, keyPath) in LiveScore.sportKeyPaths {
            guard let events = decoded[keyPath: keyPath]?.events else { continue }
            for game in events {
                guard let date = PublicGame.start(game), date >= cutoff else { continue }
                games.append(game)
            }
        }
        return games
    }

    /// Pure: indexes `games` (any order, may contain the same event twice).
    static func index(_ games: [Game], generation: Int) -> PublicSchedule {
        var byID: [String: Game] = [:]
        var ordered: [Game] = []
        ordered.reserveCapacity(games.count)
        for game in games {
            guard let id = game.idEvent, WebEscape.isSafeID(id) else { continue }
            // Tennis ships some matches under both tours with one idEvent; the page for an
            // event is one page, so the first copy wins. League lists still get both.
            if byID[id] == nil { byID[id] = game }
            ordered.append(game)
        }
        ordered.sort { (PublicGame.start($0) ?? .distantPast) < (PublicGame.start($1) ?? .distantPast) }

        var teamGames: [String: [Game]] = [:]
        var teamNames: [String: String] = [:]
        var teamLeagueCounts: [String: [String: Int]] = [:]
        var leagueGames: [String: [Game]] = [:]
        var leagueTeams: [String: Set<String>] = [:]
        var leagueFallbackNames: [String: String] = [:]
        var seenInLeague: [String: Set<String>] = [:]

        for game in ordered {
            guard let id = game.idEvent else { continue }
            if let league = game.idLeague, WebEscape.isSafeID(league) {
                // Same event twice in one league (a merge artefact) lists once.
                if seenInLeague[league, default: []].insert(id).inserted {
                    leagueGames[league, default: []].append(game)
                }
                if leagueFallbackNames[league] == nil, let name = game.strLeague { leagueFallbackNames[league] = name }
            }
            guard !game.isIndividualSport else { continue }
            let sides: [(String?, String)] = [(game.idHomeTeam, game.strHomeTeam), (game.idAwayTeam, game.strAwayTeam)]
            for (teamID, name) in sides {
                guard let teamID, WebEscape.isSafeID(teamID), !name.isEmpty, name != "TBD" else { continue }
                if teamGames[teamID]?.last?.idEvent == id { continue }
                teamGames[teamID, default: []].append(game)
                teamNames[teamID] = name
                if let league = game.idLeague, WebEscape.isSafeID(league) {
                    teamLeagueCounts[teamID, default: [:]][league, default: 0] += 1
                    leagueTeams[league, default: []].insert(teamID)
                }
            }
        }

        var teams: [String: PublicTeam] = [:]
        for (teamID, list) in teamGames {
            let name = teamNames[teamID] ?? teamID
            let counts = teamLeagueCounts[teamID] ?? [:]
            let primary = counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
            teams[teamID] = PublicTeam(id: teamID, name: name, slug: WebEscape.slug(name), primaryLeagueID: primary, games: list)
        }

        var leagues: [String: PublicLeague] = [:]
        for (leagueID, list) in leagueGames {
            let known = Int(leagueID).flatMap(Leagues.init(rawValue:))
            let name = known?.leagueName ?? leagueFallbackNames[leagueID] ?? "League \(leagueID)"
            let sport = known.map { SportType(league: $0) } ?? list.first?.sportType
            let ids = (leagueTeams[leagueID] ?? []).sorted { (teamNames[$0] ?? $0) < (teamNames[$1] ?? $1) }
            leagues[leagueID] = PublicLeague(id: leagueID, name: name, slug: WebEscape.slug(name), sport: sport, games: list, teamIDs: ids)
        }

        return PublicSchedule(generation: generation, teams: teams, leagues: leagues, games: byID)
    }
}

/// Presentation facts about a game shared by the pages and the feeds.
enum PublicGame {
    static func start(_ game: Game) -> Date? {
        if let date = game.isoDate { return date }
        guard let timestamp = game.strTimestamp else { return nil }
        return DateParsers.parse(timestamp)
    }

    static func isSoccer(_ game: Game) -> Bool {
        game.sportType == .soccer
    }

    static func isTennis(_ game: Game) -> Bool {
        game.sportType == .tennis
    }

    /// Golf tournaments and race weekends: one named event, no head-to-head.
    static func isNamedEvent(_ game: Game) -> Bool {
        game.isIndividualSport && !isTennis(game)
    }

    /// "Away @ Home" for North American team sports, "Home vs Away" for soccer and
    /// tennis, the event name for golf and racing.
    static func title(_ game: Game) -> String {
        if isNamedEvent(game) { return game.strHomeTeam }
        if isSoccer(game) || isTennis(game) {
            return game.strHomeTeam + " vs " + game.strAwayTeam
        }
        return game.strAwayTeam + " @ " + game.strHomeTeam
    }

    /// Estimated length, for DTEND and for "is it on now".
    static func duration(_ game: Game) -> TimeInterval {
        switch game.sportType {
        case .nfl: return 3.5 * 3600
        case .mlb: return 3 * 3600
        case .basketball, .hockey: return 2.5 * 3600
        case .soccer: return 2 * 3600
        case .tennis: return 2 * 3600
        case .racing: return 2 * 3600
        case .golf: return 10 * 3600
        case nil: return 3 * 3600
        }
    }

    enum Status: Equatable {
        case scheduled, live, final, calledOff(String)
    }

    static func status(_ game: Game, now: Date) -> Status {
        switch ScheduleCalendarVersion.state(of: game) {
        case .final: return .final
        case .calledOff(let label): return .calledOff(label)
        case .open:
            guard let start = start(game) else { return .scheduled }
            if game.strStatus == "in" { return .live }
            let end = endDate(game) ?? start.addingTimeInterval(duration(game))
            if start <= now, now < end { return .live }
            return .scheduled
        }
    }

    static func endDate(_ game: Game) -> Date? {
        guard let raw = game.endDate, let date = DateParsers.parse(raw) else { return nil }
        // A golf `endDate` names the last day, often at midnight: run through it.
        return date.addingTimeInterval(86_400)
    }

    static func hasScore(_ game: Game) -> Bool {
        guard let home = game.intHomeScore, let away = game.intAwayScore else { return false }
        return !home.isEmpty && !away.isEmpty
    }

    /// "Lakers 110 – 102 Celtics"-style line (order matches `title`), or the winner of
    /// a named event, or nil.
    static func result(_ game: Game) -> String? {
        if isNamedEvent(game) {
            let winner = game.strAwayTeam
            if winner.isEmpty || winner == "TBD" { return nil }
            return "Winner: " + winner
        }
        guard hasScore(game), let home = game.intHomeScore, let away = game.intAwayScore else { return nil }
        if isSoccer(game) || isTennis(game) {
            return game.strHomeTeam + " " + home + " – " + away + " " + game.strAwayTeam
        }
        return game.strAwayTeam + " " + away + " – " + home + " " + game.strHomeTeam
    }

    /// Short score for tables: "110–102" in title order.
    static func shortScore(_ game: Game) -> String? {
        guard !isNamedEvent(game), hasScore(game), let home = game.intHomeScore, let away = game.intAwayScore else { return nil }
        if isSoccer(game) || isTennis(game) { return home + "–" + away }
        return away + "–" + home
    }

    /// "2025-2026" → "2025-26"; "2026" stays.
    static func seasonLabel(_ raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 4 else { return raw }
        return String(parts[0]) + "-" + String(parts[1].suffix(2))
    }

    /// The season most of `games` from now on belong to, else the latest past one.
    static func season(of games: [Game], now: Date) -> String? {
        var counts: [String: Int] = [:]
        for game in games {
            guard let season = game.season, let start = start(game), start >= now else { continue }
            counts[season, default: 0] += 1
        }
        if let best = counts.max(by: { a, b in a.value == b.value ? a.key < b.key : a.value < b.value }) {
            return seasonLabel(best.key)
        }
        if let last = games.last(where: { $0.season != nil })?.season { return seasonLabel(last) }
        return nil
    }
}
