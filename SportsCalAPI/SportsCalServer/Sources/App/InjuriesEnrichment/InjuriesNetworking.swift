//
//  InjuriesNetworking.swift
//  SportsCalServer
//
//  Created by Umar Haroon on 4/19/26.
//

import Foundation
import Vapor
import SportsCalModel
import Logging

/// Fetches injury reports from ESPN's site API.
/// Base URL: https://site.api.espn.com/apis/site/v2/sports/{sport}/{league}/injuries
/// No auth required.
class InjuriesNetworking {
    private static let logger = Logger(label: "com.sportscal.injuries")
    private static let baseURL = "https://site.api.espn.com/apis/site/v2/sports"

    // MARK: - Response Types

    private struct InjuriesResponse: Decodable {
        let injuries: [TeamInjuries]?
    }
    private struct TeamInjuries: Decodable {
        let id: String?
        let displayName: String?
        let injuries: [ESPNInjury]?
    }
    private struct ESPNInjury: Decodable {
        let status: String?
        let date: String?
        let shortComment: String?
        let longComment: String?
        let athlete: Athlete?
        let details: Details?
    }
    private struct Athlete: Decodable {
        let displayName: String?
        let fullName: String?
        let position: Position?
        let headshot: Headshot?
    }
    private struct Position: Decodable {
        let name: String?
        let abbreviation: String?
    }
    private struct Headshot: Decodable {
        let href: String?
    }
    private struct Details: Decodable {
        let detail: String?
        let type: String?
        let location: String?
        let side: String?
        let returnDate: String?
    }

    // MARK: - Public API

    /// Fetches injuries for a league, keyed by normalized team name.
    /// Names are normalized to lowercase + collapsed whitespace to survive minor
    /// variations (e.g. "LA Clippers" vs "Los Angeles Clippers" still won't match,
    /// but "Denver Nuggets" matches itself).
    static func getInjuries(client: some Client, sport: String, league: String) async -> [String: [InjuryReport]] {
        let url = "\(baseURL)/\(sport)/\(league)/injuries"
        do {
            let response = try await client.get(URI(string: url))
            let decoded = try response.content.decode(InjuriesResponse.self)
            var result: [String: [InjuryReport]] = [:]
            for team in decoded.injuries ?? [] {
                guard let name = team.displayName else { continue }
                let reports: [InjuryReport] = (team.injuries ?? []).compactMap { injury in
                    guard let player = injury.athlete?.displayName ?? injury.athlete?.fullName,
                          let status = injury.status else { return nil }
                    return InjuryReport(
                        playerName: player,
                        position: injury.athlete?.position?.abbreviation ?? injury.athlete?.position?.name,
                        status: status,
                        detail: injury.details?.detail ?? injury.details?.type,
                        comment: injury.shortComment ?? injury.longComment,
                        headshot: injury.athlete?.headshot?.href,
                        returnDate: injury.details?.returnDate,
                        date: injury.date
                    )
                }
                if !reports.isEmpty {
                    result[normalize(name)] = reports
                }
            }
            logger.info("ESPN injuries fetched", metadata: [
                "sport": "\(sport)",
                "league": "\(league)",
                "teams": "\(result.count)",
                "reports": "\(result.values.reduce(0) { $0 + $1.count })"
            ])
            return result
        } catch {
            logger.error("ESPN injuries fetch failed", metadata: [
                "sport": "\(sport)",
                "league": "\(league)",
                "error": "\(error)"
            ])
            return [:]
        }
    }

    /// Normalizes a team name for map lookup. Lowercased, trimmed, collapsed whitespace.
    static func normalize(_ name: String) -> String {
        name.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
