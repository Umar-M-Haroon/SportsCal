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
        // Collect all completed competitions with their event IDs
        var work: [(eventId: String, competitionId: String, competitors: [Competitor])] = []
        for scoreboard in scoreboards {
            for event in scoreboard.events {
                for competition in event.competitions ?? [] {
                    let isCompleted = competition.status?.type.completed ?? false
                    guard isCompleted, let competitors = competition.competitors, !competitors.isEmpty else { continue }
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


