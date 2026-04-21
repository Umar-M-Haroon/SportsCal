//
//  File.swift
//  
//
//  Created by Umar Haroon on 2/28/23.
//

import Foundation
import Vapor
import SportsCalModel
import Logging

class ESPNNetworking {
    private static let logger = Logger(label: "com.sportscal.espn")

    @available(*, deprecated, message: "use league lookup")
    static func getScoreboard<Output: Decodable>(req: some Client, DecodeType: Output.Type, scoreType: SportType) async throws -> Output {
        let urlString = "http://site.api.espn.com/apis/site/v2/sports/"
        guard let sport = decodeSportToPath(sport: scoreType) else { throw NetworkError.invalidLeague }
        let scoreboard = "/scoreboard"
        let fullString = urlString + sport + scoreboard
        do {
            let response = try await req.get(URI(string: fullString)) { req in
                try req.query.encode(["limit" : 500])
            }
            return try response.content.decode(DecodeType.self)
        } catch {
            logger.error("ESPN scoreboard fetch failed", metadata: [
                "sport": "\(scoreType)",
                "url": "\(fullString)",
                "error": "\(error)"
            ])
            throw error
        }
    }

    static func getScoreboard<Output: Decodable>(req: some Client, DecodeType: Output.Type, league: Leagues, dates: Int? = nil) async throws -> Output {
        if let espnSlug = league.espnSlug {
            let urlString = "http://site.api.espn.com/apis/site/v2/sports"
            let scoreboard = "scoreboard"
            let sport = league.sport
            let fullString = [urlString, sport, espnSlug, scoreboard].joined(separator: "/")
            do {
                var uri = URI(string: fullString)
                uri.query = "limit=500"
                if let dates {
                    uri.query! += "&dates=\(dates)"
                } else if league.usesSingleYearSeason {
                    let year = Calendar.current.component(.year, from: Date())
                    uri.query! += "&dates=\(year)"
                }
                let response = try await req.get(uri)
                return try response.content.decode(DecodeType.self)
            } catch {
                logger.error("ESPN scoreboard fetch failed", metadata: [
                    "league": "\(league)",
                    "url": "\(fullString)",
                    "error": "\(error)"
                ])
                throw error
            }
        }
        throw NetworkError.invalidLeague
    }

    static func getTeam<Output: Decodable>(req: some Client, DecodeType: Output.Type, league: Leagues) async throws -> Output {
        if let espnSlug = league.espnSlug {
            let urlString = "http://site.api.espn.com/apis/site/v2/sports"
            let scoreboard = "teams"
            let sport = league.sport
            let fullString = [urlString, sport, espnSlug, scoreboard].joined(separator: "/")
            do {
                let response = try await req.get(URI(string: fullString)) { req in
                    try req.query.encode(["limit" : 500])
                }
                return try response.content.decode(DecodeType.self)
            } catch {
                logger.error("ESPN team fetch failed", metadata: [
                    "league": "\(league)",
                    "url": "\(fullString)",
                    "error": "\(error)"
                ])
                throw error
            }
        }
        throw NetworkError.invalidLeague
    }

    static func getStandings<Output: Decodable>(req: some Client, DecodeType: Output.Type, league: Leagues) async throws -> Output {
        if let espnSlug = league.espnSlug {
            let urlString = "http://site.api.espn.com/apis/v2/sports"
            let sport = league.sport
            let fullString = [urlString, sport, espnSlug, "standings"].joined(separator: "/")
            do {
                let response = try await req.get(URI(string: fullString))
                return try response.content.decode(DecodeType.self)
            } catch {
                logger.error("ESPN standings fetch failed", metadata: [
                    "league": "\(league)",
                    "url": "\(fullString)",
                    "error": "\(error)"
                ])
                throw error
            }
        }
        throw NetworkError.invalidLeague
    }

    // MARK: - Leaders (Stat Leaders per Category)

    static func getLeaders<Output: Decodable>(req: some Client, DecodeType: Output.Type, league: Leagues) async throws -> Output {
        if let espnSlug = league.espnSlug {
            let urlString = "http://site.api.espn.com/apis/site/v2/sports"
            let sport = league.sport
            let fullString = [urlString, sport, espnSlug, "leaders"].joined(separator: "/")
            do {
                let response = try await req.get(URI(string: fullString))
                return try response.content.decode(DecodeType.self)
            } catch {
                logger.error("ESPN leaders fetch failed", metadata: [
                    "league": "\(league)",
                    "url": "\(fullString)",
                    "error": "\(error)"
                ])
                throw error
            }
        }
        throw NetworkError.invalidLeague
    }

    // MARK: - F1 Core Data (Constructors + Timing)

    /// Minimal struct for decoding the ESPN core API competitor response (vehicle field only)
    private struct CoreCompetitor: Decodable {
        var vehicle: Vehicle?
        struct Vehicle: Decodable {
            var manufacturer: String?
        }
    }

    /// Minimal struct for decoding competitor statistics from the ESPN core API
    private struct CoreStatistics: Decodable {
        var splits: Splits?
        struct Splits: Decodable {
            var categories: [Category]?
        }
        struct Category: Decodable {
            var stats: [Stat]?
        }
        struct Stat: Decodable {
            var name: String?
            var displayValue: String?
        }

        /// Returns the display value for a stat by name (e.g. "behindTime", "totalTime")
        func statValue(named name: String) -> String? {
            for category in splits?.categories ?? [] {
                for stat in category.stats ?? [] {
                    if stat.name == name { return stat.displayValue }
                }
            }
            return nil
        }
    }

    /// Fetches constructor (vehicle manufacturer) names for F1 competitors from the ESPN core API.
    /// Returns a dictionary mapping competitor ID → manufacturer name (e.g. "McLaren", "Red Bull").
    /// Falls back to an empty dictionary on failure.
    static func getF1ConstructorMap(req: some Client, scoreboard: Scoreboard) async -> [String: String] {
        // Find the first Race competition that has competitors
        var targetEvent: Event?
        var targetCompetition: Competition?
        for event in scoreboard.events {
            guard let competitions = event.competitions else { continue }
            for competition in competitions {
                if competition.type?.abbreviation == "Race",
                   let competitors = competition.competitors, !competitors.isEmpty {
                    targetEvent = event
                    targetCompetition = competition
                    break
                }
            }
            if targetCompetition != nil { break }
        }

        // If no Race found, try the first competition with competitors (e.g. qualifying)
        if targetCompetition == nil {
            for event in scoreboard.events {
                if let competition = event.competitions?.first(where: { ($0.competitors?.isEmpty == false) }) {
                    targetEvent = event
                    targetCompetition = competition
                    break
                }
            }
        }

        guard let event = targetEvent, let competition = targetCompetition,
              let competitors = competition.competitors else {
            return [:]
        }

        var constructorMap: [String: String] = [:]
        for competitor in competitors {
            let urlString = "https://sports.core.api.espn.com/v2/sports/racing/leagues/f1/events/\(event.id)/competitions/\(competition.id)/competitors/\(competitor.id)?lang=en&region=us"
            do {
                let response = try await req.get(URI(string: urlString))
                let coreCompetitor = try response.content.decode(CoreCompetitor.self)
                if let manufacturer = coreCompetitor.vehicle?.manufacturer, !manufacturer.isEmpty {
                    constructorMap[competitor.id] = manufacturer
                }
            } catch {
                logger.warning("Failed to fetch F1 constructor for competitor \(competitor.id)", metadata: [
                    "error": "\(error)"
                ])
            }
        }

        logger.info("F1 constructor map fetched", metadata: [
            "count": "\(constructorMap.count)",
            "total": "\(competitors.count)"
        ])
        return constructorMap
    }

    /// Fetches timing/gap data for all completed F1 sessions from the ESPN core API statistics endpoint.
    /// Returns `[competitionId: [competitorId: gapString]]`.
    /// P1 gets totalTime (e.g. "1:42:06.304"), P2+ gets behindTime (e.g. "+0.895").
    static func getF1TimingMap(req: some Client, scoreboards: [Scoreboard]) async -> [String: [String: String]] {
        // Collect completed and in-progress competitions with their event IDs
        var work: [(eventId: String, competitionId: String, competitors: [Competitor])] = []
        for scoreboard in scoreboards {
            for event in scoreboard.events {
                for competition in event.competitions ?? [] {
                    let isCompleted = competition.status?.type.completed ?? false
                    let isInProgress = competition.status?.type.state == "in"
                    guard (isCompleted || isInProgress), let competitors = competition.competitors, !competitors.isEmpty else { continue }
                    work.append((eventId: event.id, competitionId: competition.id, competitors: competitors))
                }
            }
        }

        guard !work.isEmpty else { return [:] }
        logger.info("Fetching F1 timing data", metadata: [
            "competitions": "\(work.count)",
            "totalRequests": "\(work.reduce(0) { $0 + $1.competitors.count })"
        ])

        var timingMap: [String: [String: String]] = [:]

        for item in work {
            // Fetch all competitors for this competition concurrently
            var competitionTiming: [String: String] = [:]
            await withTaskGroup(of: (String, String?).self) { group in
                for competitor in item.competitors {
                    group.addTask {
                        let urlString = "https://sports.core.api.espn.com/v2/sports/racing/leagues/f1/events/\(item.eventId)/competitions/\(item.competitionId)/competitors/\(competitor.id)/statistics?lang=en&region=us"
                        do {
                            let response = try await req.get(URI(string: urlString))
                            let stats = try response.content.decode(CoreStatistics.self)
                            // P1 shows total time, P2+ show gap behind leader
                            if let behind = stats.statValue(named: "behindTime"), behind != "+0.000" {
                                return (competitor.id, behind)
                            } else if let total = stats.statValue(named: "totalTime") {
                                return (competitor.id, total)
                            }
                            // Fallback: check for laps behind or status (DNF/DNS/+N Laps)
                            if let lapsDown = stats.statValue(named: "lapsDown"), !lapsDown.isEmpty, lapsDown != "0" {
                                return (competitor.id, "+\(lapsDown) Lap\(lapsDown == "1" ? "" : "s")")
                            }
                            if let status = stats.statValue(named: "status"), !status.isEmpty,
                               status != "Running" && status != "Active" {
                                return (competitor.id, status) // e.g. "DNF", "DNS", "Retired"
                            }
                            return (competitor.id, nil)
                        } catch {
                            return (competitor.id, nil)
                        }
                    }
                }
                for await (competitorId, gap) in group {
                    if let gap {
                        competitionTiming[competitorId] = gap
                    }
                }
            }
            if !competitionTiming.isEmpty {
                timingMap[item.competitionId] = competitionTiming
            }
        }

        logger.info("F1 timing map fetched", metadata: [
            "competitions": "\(timingMap.count)"
        ])
        return timingMap
    }

    // MARK: - Play-by-Play Summary (NBA / NFL / NHL / MLB)

    /// Fetches the full play-by-play array from ESPN's per-event summary endpoint.
    /// Returns only the fields we consume (`plays[]`) — the full summary has many more.
    static func getPlayByPlaySummary(
        req: some Client,
        sport: String,
        league: String,
        eventId: String
    ) async throws -> ESPNSummaryResponse {
        let urlString = "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(league)/summary?event=\(eventId)"
        do {
            let response = try await req.get(URI(string: urlString))
            return try response.content.decode(ESPNSummaryResponse.self)
        } catch {
            logger.error("ESPN play-by-play summary fetch failed", metadata: [
                "sport": "\(sport)",
                "league": "\(league)",
                "eventId": "\(eventId)",
                "url": "\(urlString)",
                "error": "\(error)"
            ])
            throw error
        }
    }

    // MARK: - Golf Summary (per-event detail with hole-by-hole data)

    /// Fetches detailed golf tournament summary including course info, hole-by-hole scores, and round stats.
    static func getGolfSummary(req: some Client, eventId: String) async throws -> GolfSummaryResponse {
        let urlString = "http://site.api.espn.com/apis/site/v2/sports/golf/pga/summary?event=\(eventId)"
        do {
            let response = try await req.get(URI(string: urlString))
            return try response.content.decode(GolfSummaryResponse.self)
        } catch {
            logger.error("ESPN golf summary fetch failed", metadata: [
                "eventId": "\(eventId)",
                "url": "\(urlString)",
                "error": "\(error)"
            ])
            throw error
        }
    }

    // MARK: - Golf Summary Response Models

    struct GolfSummaryResponse: Codable {
        var courses: [GolfSummaryCourse]?
        var rounds: [GolfSummaryRound]?
    }

    struct GolfSummaryCourse: Codable {
        var name: String?
        var par: Int?
        var holes: [GolfSummaryCourseHole]?
    }

    struct GolfSummaryCourseHole: Codable {
        var number: Int
        var par: Int
        var yardage: Int?
    }

    struct GolfSummaryRound: Codable {
        var number: Int?
        var displayName: String?
        var competitors: [GolfSummaryCompetitor]?
    }

    struct GolfSummaryCompetitor: Codable {
        var id: String?
        var athlete: GolfSummaryAthlete?
        var score: String?
        var status: GolfSummaryCompetitorStatus?
        var linescores: [GolfSummaryLinescore]?
        var statistics: [GolfSummaryStatCategory]?
    }

    struct GolfSummaryAthlete: Codable {
        var id: String?
        var displayName: String?
    }

    struct GolfSummaryCompetitorStatus: Codable {
        var period: Int?
        var displayValue: String?
        var thru: Int?
    }

    struct GolfSummaryLinescore: Codable {
        var period: Int?   // hole number
        var value: Int?    // strokes on this hole
    }

    struct GolfSummaryStatCategory: Codable {
        var name: String?
        var displayName: String?
        var stats: [GolfSummaryStat]?
    }

    struct GolfSummaryStat: Codable {
        var name: String?
        var displayName: String?
        var value: Double?
        var displayValue: String?
    }

    static func decodeSportToPath(sport: SportType) -> String? {
        switch sport {
        case .basketball:
            return "basketball/nba"
        case .hockey:
            return "hockey/nhl"
        case .mlb:
            return "baseball/mlb"
        case .nfl:
            return "football/nfl"
        case .golf:
            return "golf/pga"
        case .tennis:
            return nil
        case .racing:
            return "racing/f1"
        default:
            return nil
        }
    }
}


