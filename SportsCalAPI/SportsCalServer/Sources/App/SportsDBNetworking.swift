//
//  SportsDBNetworking.swift
//  
//
//  Created by Umar Haroon on 10/21/22.
//

import Foundation
import Vapor
import SportsCalModel
import OrderedCollections
import Logging

class SportsDBNetworking {
    private static let logger = Logger(label: "com.sportscal.sportsdb")
    public enum LiveScoreType: String, CaseIterable {
        case soccer = "Soccer"
        case hockey = "Ice_Hockey"
        case basketball = "Basketball"
        case nfl = "4391"
        case mlb = "4424"
        case golf = "Golf"
        case tennis = "Tennis"
        case motorsport = "Motorsport"

        var isLeague: Bool {
            switch self {
            case .basketball, .hockey, .soccer, .golf, .tennis, .motorsport:
                return false
            case .nfl, .mlb:
                return true
            }
        }
    }

    /// Calculate the current season string based on the current date
    /// Sports seasons typically start in fall (Sept/Oct) and end in spring (April/May)
    /// Returns format: "YYYY-YYYY" (e.g., "2024-2025")
    private static func getCurrentSeason() -> String {
        let now = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        // If we're in Jan-Jun, we're in the second half of the season (started previous year)
        // If we're in Jul-Dec, we're in the first half of the season (will end next year)
        let startYear = month <= 6 ? year - 1 : year
        let endYear = startYear + 1

        return "\(startYear)-\(endYear)"
    }

    /// Get the current single-year season (for tennis, etc.)
    /// Returns format: "YYYY" (e.g., "2026")
    private static func getCurrentSingleYearSeason() -> String {
        let now = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        return "\(year)"
    }

    /// Get the previous season string
    private static func getPreviousSeason(from season: String) -> String? {
        let components = season.split(separator: "-")
        if components.count == 2, let startYear = Int(components[0]) {
            return "\(startYear - 1)-\(startYear)"
        }
        // Single-year format
        if let year = Int(season) {
            return "\(year - 1)"
        }
        return nil
    }

    /// Get the next season string
    private static func getNextSeason(from season: String) -> String? {
        let components = season.split(separator: "-")
        if components.count == 2, let endYear = Int(components[1]) {
            return "\(endYear)-\(endYear + 1)"
        }
        // Single-year format
        if let year = Int(season) {
            return "\(year + 1)"
        }
        return nil
    }
    
    static func callLiveScore<Output: Decodable>(req: some Client, DecodeType: Output.Type, scoreType: LiveScoreType) async throws -> Output? {
        // v2 format: /livescore/{sport_name} or /livescore/{league_id}
        let endpoint = scoreType.rawValue
        let urlString = "https://www.thesportsdb.com/api/v2/json/livescore/\(endpoint)"

        logger.info("🌐 Fetching live scores (v2)", metadata: [
            "url": "\(urlString)",
            "scoreType": "\(scoreType.rawValue)",
            "isLeague": "\(scoreType.isLeague)"
        ])

        do {
            let response = try await req.get(URI(string: urlString)) { req in
                if let apiKey = Environment.get("SportsDB_API_KEY") {
                    req.headers.add(name: "X-API-KEY", value: apiKey)
                }
            }

            logger.info("✅ Live scores response received", metadata: [
                "status": "\(response.status.code)",
                "scoreType": "\(scoreType.rawValue)"
            ])

            // Try to decode as V2 response (with "livescore" field)
            if let v2Response = try? response.content.decode(V2LiveScoreResponse.self) {
                logger.info("🎯 Successfully decoded v2 live scores", metadata: [
                    "scoreType": "\(scoreType.rawValue)",
                    "count": "\(v2Response.livescore.count)"
                ])
                // Convert to expected output type (LiveEvent)
                let liveEvent = v2Response.toLiveEvent()
                return liveEvent as? Output
            }

            // Try to decode as "No data found" message
            if let noDataResponse = try? response.content.decode(V2NoDataResponse.self) {
                logger.info("ℹ️ No live score data found", metadata: [
                    "scoreType": "\(scoreType.rawValue)",
                    "message": "\(noDataResponse.message)"
                ])
                // Return empty LiveEvent
                let emptyLiveEvent = LiveEvent(events: [])
                return emptyLiveEvent as? Output
            }

            // If both fail, log error
            logger.error("❌ Failed to decode live scores response", metadata: [
                "scoreType": "\(scoreType.rawValue)",
                "responseStatus": "\(response.status.code)"
            ])

            // Log response body on decode failure
            if let body = response.body, let bodyString = body.getString(at: body.readerIndex, length: body.readableBytes) {
                logger.error("❌ Response body that failed to decode", metadata: [
                    "body": "\(bodyString.prefix(1000))"
                ])
            }

            return nil
        } catch {
            logger.error("❌ Live score fetch failed", metadata: [
                "url": "\(urlString)",
                "scoreType": "\(scoreType.rawValue)",
                "error": "\(error)"
            ])
            throw error
        }
    }
    
    static func getSchedule<Output>(app: Application, DecodeType: Output.Type, league: Int, singleYearSeason: Bool = false) async throws -> [Output?] where Output: Codable, Output: Hashable {
        // v2 format: /schedule/league/{league_id}/{season}

        // Calculate current season and adjacent seasons
        let currentSeason = singleYearSeason ? getCurrentSingleYearSeason() : getCurrentSeason()
        let previousSeason = getPreviousSeason(from: currentSeason)
        let nextSeason = getNextSeason(from: currentSeason)

        logger.info("📅 Fetching schedule (v2)", metadata: [
            "league": "\(league)",
            "currentSeason": "\(currentSeason)",
            "previousSeason": "\(previousSeason ?? "N/A")",
            "nextSeason": "\(nextSeason ?? "N/A")"
        ])

        var results: [Output?] = []

        // Helper function to fetch a single season
        func fetchSeason(_ season: String, seasonType: String) async -> Output? {
            do {
                let urlString = "https://www.thesportsdb.com/api/v2/json/schedule/league/\(league)/\(season)"

                logger.info("📅 Fetching \(seasonType) season (\(season))", metadata: [
                    "url": "\(urlString)",
                    "league": "\(league)"
                ])

                let response = try await app.client.get(URI(string: urlString)) { req in
                    if let apiKey = Environment.get("SportsDB_API_KEY") {
                        req.headers.add(name: "X-API-KEY", value: apiKey)
                    }
                }

                logger.info("✅ \(seasonType) season response received", metadata: [
                    "status": "\(response.status.code)",
                    "league": "\(league)",
                    "season": "\(season)"
                ])

                // Try to decode as V2 response (with "schedule" field)
                if let v2Response = try? response.content.decode(V2ScheduleResponse.self) {
                    logger.info("🎯 Successfully decoded v2 \(seasonType) season", metadata: [
                        "league": "\(league)",
                        "season": "\(season)",
                        "count": "\(v2Response.schedule.count)"
                    ])
                    // Convert to expected output type (LiveEvent)
                    let liveEvent = v2Response.toLiveEvent()
                    return liveEvent as? Output
                } else if let noDataResponse = try? response.content.decode(V2NoDataResponse.self) {
                    logger.info("ℹ️ No \(seasonType) season data found", metadata: [
                        "league": "\(league)",
                        "season": "\(season)",
                        "message": "\(noDataResponse.message)"
                    ])
                } else {
                    logger.error("❌ Failed to decode \(seasonType) season response", metadata: [
                        "league": "\(league)",
                        "season": "\(season)",
                        "status": "\(response.status.code)"
                    ])

                    // Log response body on decode failure
                    if let body = response.body, let bodyString = body.getString(at: body.readerIndex, length: body.readableBytes) {
                        logger.error("❌ \(seasonType) season response body", metadata: [
                            "body": "\(bodyString.prefix(1000))"
                        ])
                    }
                }
            } catch {
                logger.error("❌ \(seasonType) season fetch failed", metadata: [
                    "league": "\(league)",
                    "season": "\(season)",
                    "error": "\(error)"
                ])
            }
            return nil
        }

        // Fetch previous season (if available)
        if let prevSeason = previousSeason {
            if let response = await fetchSeason(prevSeason, seasonType: "previous") {
                results.append(response)
            }
        }

        // Fetch current season
        if let response = await fetchSeason(currentSeason, seasonType: "current") {
            results.append(response)
        }

        // Fetch next season (if available)
        if let nxtSeason = nextSeason {
            if let response = await fetchSeason(nxtSeason, seasonType: "next") {
                results.append(response)
            }
        }

        // Deduplicate results using OrderedSet
        let uniqueResults = Array(OrderedSet(results.compactMap { $0 }))

        logger.info("📊 Schedule fetch complete", metadata: [
            "league": "\(league)",
            "currentSeason": "\(currentSeason)",
            "resultCount": "\(uniqueResults.count)"
        ])

        return uniqueResults
    }
    static func getTeamInfoForLeague<Output: Decodable>(app: Application, DecodeType: Output.Type, league: Int) async throws -> Output? {
        // v2 format: /list/teams/{idLeague}
        let urlString = "https://www.thesportsdb.com/api/v2/json/list/teams/\(league)"

        logger.info("🏆 Fetching team info for league (v2)", metadata: [
            "url": "\(urlString)",
            "league": "\(league)"
        ])

        do {
            let response = try await app.client.get(URI(string: urlString)) { req in
                if let apiKey = Environment.get("SportsDB_API_KEY") {
                    req.headers.add(name: "X-API-KEY", value: apiKey)
                }
            }

            logger.info("✅ Team info response received", metadata: [
                "status": "\(response.status.code)",
                "league": "\(league)"
            ])

            // Try to decode as V2 response (with "list" field)
            if let v2Response = try? response.content.decode(V2TeamsResponse.self) {
                logger.info("🎯 Successfully decoded v2 team info", metadata: [
                    "league": "\(league)",
                    "count": "\(v2Response.list.count)"
                ])
                // Convert to expected output type (Teams)
                let teams = v2Response.toTeams()
                return teams as? Output
            }

            // Try to decode as "No data found" message
            if let noDataResponse = try? response.content.decode(V2NoDataResponse.self) {
                logger.info("ℹ️ No team info data found", metadata: [
                    "league": "\(league)",
                    "message": "\(noDataResponse.message)"
                ])
                // Return empty Teams
                let emptyTeams = Teams(teams: [])
                return emptyTeams as? Output
            }

            // If both fail, log error
            logger.error("❌ Failed to decode team info response", metadata: [
                "league": "\(league)",
                "status": "\(response.status.code)"
            ])

            // Log response body on decode failure
            if let body = response.body, let bodyString = body.getString(at: body.readerIndex, length: body.readableBytes) {
                logger.error("❌ Team info response body", metadata: [
                    "body": "\(bodyString.prefix(1000))"
                ])
            }

            return nil
        } catch {
            logger.error("❌ Team info fetch failed", metadata: [
                "url": "\(urlString)",
                "league": "\(league)",
                "error": "\(error)"
            ])
            return nil
        }
    }
}
