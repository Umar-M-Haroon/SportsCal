//
//  FantasyService.swift
//  SportsCalServer
//
//  Writes fantasy lines from the ESPN summaries the play-by-play pass already fetches,
//  and assembles `/fantasy` slates from the archive: the week's lines, positions from
//  ESPN rosters, and each player's season average.
//
//  NFL only for now (`FantasyScoring.supports`). Slates are weeks of the regular season
//  (ESPN season type 2) or postseason rounds (type 3).
//

import Foundation
import Logging
import SportsCalModel
import Redis
import Vapor

enum FantasyService {
    static let logger = Logger(label: "com.sportscal.fantasy")

    /// ESPN slugs per sport fantasy scores.
    static func espnPath(for sport: SportType) -> (sport: String, league: String)? {
        switch sport {
        case .nfl: return ("football", "nfl")
        default: return nil
        }
    }

    static func redisKey(_ name: String, isDebug: Bool) -> RedisKey {
        RedisKey((isDebug ? "debug-" : "") + "Fantasy-" + name)
    }

    // MARK: - Ingest

    /// Logs one game's lines from its summary. Best-effort: never throws into the
    /// play-by-play pass that called it.
    static func ingest(
        summary: ESPNSummaryResponse,
        sport: SportType,
        espnEventID: String,
        tsdbEventID: String?,
        app: Application,
        isDebug: Bool
    ) async {
        guard let archive = app.fantasyArchive, let path = espnPath(for: sport) else { return }
        let base = FantasyStatLines.lines(summary: summary, sport: sport, eventID: espnEventID)
        guard !base.isEmpty else { return }
        let context = FantasyStatLines.context(header: summary.header, sport: sport)
        guard let season = context.season else { return }
        let rosters = await FantasyRosters.shared.current(app: app, sport: sport, isDebug: isDebug)
        let lines = rosters.fillPositions(FantasyStatLines.applying(context, tsdbEventID: tsdbEventID, to: base))
        let slot = FantasyArchive.Slot(
            league: path.league, season: season, seasonType: context.seasonType ?? 2,
            week: context.week
        )
        do {
            try await archive.replace(eventID: espnEventID, slot: slot, isFinal: context.state == "post", lines: lines)
        } catch {
            logger.warning("Fantasy lines write failed", metadata: ["eventID": "\(espnEventID)", "error": "\(error)"])
        }
    }

    // MARK: - Slates

    static let slateCacheSeconds = 30

    /// A week's slate. `week` nil → the week ESPN's scoreboard is on now.
    static func slate(sport: SportType, week: Int?, seasonType: Int?, app: Application, isDebug: Bool) async throws -> FantasySlate {
        guard let path = espnPath(for: sport), let archive = app.fantasyArchive else { throw Abort(.notFound) }
        let board = try await FantasyScoreboard.week(sport: sport, week: week, seasonType: seasonType, app: app, isDebug: isDebug)
        let cacheKey = redisKey("Slate-\(path.league)-\(board.season)-\(board.seasonType)-\(board.week ?? 0)", isDebug: isDebug)
        if let cached = try? await app.redis.get(cacheKey, asJSON: FantasySlate.self) {
            return cached
        }

        let slot = FantasyArchive.Slot(league: path.league, season: board.season, seasonType: board.seasonType, week: board.week)
        var lines = try await archive.lines(slot: slot)
        let rosters = await FantasyRosters.shared.current(app: app, sport: sport, isDebug: isDebug)
        lines = rosters.fillPositions(lines)
        // The scoreboard's clock is fresher than a final-pass row for games still live.
        lines = lines.map { board.refreshing($0) }
        let averages = try await archive.seasonAverages(
            league: path.league, season: board.season,
            athleteIDs: Set(lines.map(\.athleteID)), excludingEvents: Set(lines.map(\.eventID))
        )
        lines = lines.map { line in
            var line = line
            if let average = averages[line.athleteID] {
                line.seasonAverage = average.stats
                line.seasonGames = average.games
            }
            return line
        }

        var weeks = try await archive.weeks(league: path.league, season: board.season, seasonType: board.seasonType)
        if let current = board.week, !weeks.contains(current) { weeks.append(current) }
        let slate = FantasySlate(
            sport: sport,
            season: board.season,
            week: board.week,
            label: board.label,
            generatedAt: Date(),
            players: lines,
            games: board.games,
            availableWeeks: weeks.sorted()
        )
        try? await app.redis.setex(cacheKey, toJSON: slate, expirationInSeconds: slateCacheSeconds)
        return slate
    }

    /// One game's lines with averages, by ESPN or TheSportsDB event ID.
    static func eventLines(eventID: String, app: Application, isDebug: Bool) async throws -> [FantasyPlayerLine] {
        guard let archive = app.fantasyArchive else { throw Abort(.notFound) }
        var lines = try await archive.lines(eventID: eventID)
        if lines.isEmpty,
           let mapping = await ESPNEventMapStore.lookup(eventID: eventID, kv: app.kv, isDebug: isDebug) {
            lines = try await archive.lines(eventID: mapping.espnEventID)
        }
        guard let first = lines.first, let season = first.gameDate.map(seasonYear(for:)) else { return lines }
        let averages = try await archive.seasonAverages(
            league: "nfl", season: season, athleteIDs: Set(lines.map(\.athleteID)), excludingEvents: [first.eventID]
        )
        let rosters = await FantasyRosters.shared.current(app: app, sport: .nfl, isDebug: isDebug)
        return rosters.fillPositions(lines).map { line in
            var line = line
            if let average = averages[line.athleteID] {
                line.seasonAverage = average.stats
                line.seasonGames = average.games
            }
            return line
        }
    }

    /// The NFL season a game belongs to: January and February games are last year's.
    static func seasonYear(for date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 2026
        return (components.month ?? 9) <= 2 ? year - 1 : year
    }
}

// MARK: - Scoreboard weeks

/// The slice of an ESPN week scoreboard a slate needs.
struct FantasyScoreboard: Codable, Sendable {
    var season: Int
    var seasonType: Int
    var week: Int?
    var label: String
    var games: [FantasySlate.Game]

    static let cacheSeconds = 60

    static func week(sport: SportType, week: Int?, seasonType: Int?, app: Application, isDebug: Bool) async throws -> FantasyScoreboard {
        guard let path = FantasyService.espnPath(for: sport) else { throw Abort(.notFound) }
        let key = FantasyService.redisKey("Board-\(path.league)-\(seasonType ?? 0)-\(week ?? 0)", isDebug: isDebug)
        if let cached = try? await app.redis.get(key, asJSON: FantasyScoreboard.self) {
            return cached
        }
        var url = "https://site.api.espn.com/apis/site/v2/sports/\(path.sport)/\(path.league)/scoreboard"
        if let week {
            url += "?week=\(week)&seasontype=\(seasonType ?? 2)"
        }
        let response = try await ESPNNetworking.performGet(app.client, URI(string: url))
        let raw = try response.content.decode(Raw.self)
        let board = FantasyScoreboard(raw: raw)
        try? await app.redis.setex(key, toJSON: board, expirationInSeconds: cacheSeconds)
        return board
    }

    init(season: Int, seasonType: Int, week: Int?, label: String, games: [FantasySlate.Game]) {
        self.season = season
        self.seasonType = seasonType
        self.week = week
        self.label = label
        self.games = games
    }

    init(raw: Raw) {
        season = raw.season?.year ?? Calendar.current.component(.year, from: Date())
        seasonType = raw.season?.type ?? 2
        week = raw.week?.number
        switch (seasonType, week) {
        case (3, let week?): label = Self.postseasonLabel(week)
        case (_, let week?): label = "Week \(week)"
        default: label = "This week"
        }
        games = (raw.events ?? []).map { event in
            let competition = event.competitions?.first
            let home = competition?.competitors?.first { $0.homeAway == "home" }
            let away = competition?.competitors?.first { $0.homeAway == "away" }
            return FantasySlate.Game(
                id: event.id,
                date: event.date.flatMap(DateParsers.parse),
                state: event.status?.type?.state,
                status: event.status?.type?.shortDetail,
                homeTeamID: home?.team?.id, awayTeamID: away?.team?.id,
                homeAbbreviation: home?.team?.abbreviation, awayAbbreviation: away?.team?.abbreviation
            )
        }
        var progress: [String: Double] = [:]
        for event in raw.events ?? [] {
            guard event.status?.type?.state == "in", let period = event.status?.period else { continue }
            progress[event.id] = FantasyStatLines.regulationProgress(sport: .nfl, period: period, clock: event.status?.clock ?? 0)
        }
        liveProgress = progress
    }

    /// Live games' progress, by ESPN event ID.
    var liveProgress: [String: Double] = [:]

    static func postseasonLabel(_ week: Int) -> String {
        switch week {
        case 1: return "Wild Card"
        case 2: return "Divisional"
        case 3: return "Conference"
        case 5: return "Super Bowl"
        default: return "Postseason week \(week)"
        }
    }

    /// `line` with this board's state, status and progress for its game.
    func refreshing(_ line: FantasyPlayerLine) -> FantasyPlayerLine {
        guard let game = games.first(where: { $0.id == line.eventID }) else { return line }
        var line = line
        line.gameState = game.state ?? line.gameState
        line.gameStatus = game.status ?? line.gameStatus
        if game.state == "post" {
            line.gameProgress = 1
        } else if let progress = liveProgress[line.eventID] {
            line.gameProgress = progress
        }
        return line
    }

    struct Raw: Decodable {
        var season: Season?
        var week: Week?
        var events: [Event]?

        struct Season: Decodable { var year: Int?; var type: Int? }
        struct Week: Decodable { var number: Int? }
        struct Event: Decodable {
            var id: String
            var date: String?
            var status: Status?
            var competitions: [Competition]?
        }
        struct Status: Decodable {
            var clock: Double?
            var period: Int?
            var type: StatusType?
        }
        struct StatusType: Decodable { var state: String?; var shortDetail: String? }
        struct Competition: Decodable { var competitors: [Competitor]? }
        struct Competitor: Decodable {
            var homeAway: String?
            var team: Team?
        }
        struct Team: Decodable { var id: String?; var abbreviation: String? }
    }
}
