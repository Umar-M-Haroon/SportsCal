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
        let id: String?
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
        let team: AthleteTeam?
        let links: [Link]?
    }
    private struct AthleteTeam: Decodable {
        let abbreviation: String?
    }
    private struct Link: Decodable {
        let href: String?
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

    /// Every open injury in a league. NFL practice reports list fully healthy players
    /// as "Active"; those aren't injuries and are dropped.
    static func getPlayerInjuries(client: some Client, sport: String, league: String) async -> [PlayerInjury] {
        let url = "\(baseURL)/\(sport)/\(league)/injuries"
        do {
            let response = try await client.get(URI(string: url))
            let decoded = try response.content.decode(InjuriesResponse.self)
            let injuries = parse(decoded.injuries ?? [], league: league)
            logger.info("ESPN injuries fetched", metadata: [
                "sport": "\(sport)", "league": "\(league)", "reports": "\(injuries.count)"
            ])
            return injuries
        } catch {
            logger.error("ESPN injuries fetch failed", metadata: [
                "sport": "\(sport)", "league": "\(league)", "error": "\(error)"
            ])
            return []
        }
    }

    /// Parses a raw `/injuries` response body (tests use this with saved responses).
    static func parse(_ data: Data, league: String) throws -> [PlayerInjury] {
        parse(try JSONDecoder().decode(InjuriesResponse.self, from: data).injuries ?? [], league: league)
    }

    private static func parse(_ teams: [TeamInjuries], league: String) -> [PlayerInjury] {
        var result: [PlayerInjury] = []
        for team in teams {
            guard let teamName = team.displayName else { continue }
            let entries: [ESPNInjury] = team.injuries ?? []
            for injury in entries {
                guard let player = injury.athlete?.displayName ?? injury.athlete?.fullName,
                      let status = injury.status, status != "Active" else { continue }
                var athleteID: String? = nil
                for link in injury.athlete?.links ?? [] {
                    if let id = Self.athleteID(fromLink: link.href) { athleteID = id; break }
                }
                result.append(PlayerInjury(
                    id: injury.id ?? "\(league):\(teamName):\(player)",
                    athleteID: athleteID,
                    playerName: player,
                    position: injury.athlete?.position?.abbreviation ?? injury.athlete?.position?.name,
                    headshot: injury.athlete?.headshot?.href,
                    league: league,
                    teamName: teamName,
                    teamAbbreviation: injury.athlete?.team?.abbreviation,
                    status: status,
                    bodyPart: known(injury.details?.type),
                    injury: known(injury.details?.detail),
                    side: known(injury.details?.side),
                    returnDate: injury.details?.returnDate,
                    summary: injury.shortComment.flatMap(meaningfulComment),
                    details: injury.longComment.flatMap(meaningfulComment),
                    updated: injury.date
                ))
            }
        }
        return result
    }

    /// ESPN fills unknown fields with "Not Specified".
    static func known(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value != "Not Specified" else { return nil }
        return value
    }

    /// NFL entries often carry just the status as the comment ("questionable").
    static func meaningfulComment(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 20 ? trimmed : nil
    }

    /// ".../player/_/id/3146557/jock-landale" → "3146557".
    static func athleteID(fromLink href: String?) -> String? {
        guard let href, let range = href.range(of: "/id/") else { return nil }
        let id = href[range.upperBound...].prefix { $0.isNumber }
        return id.isEmpty ? nil : String(id)
    }

    /// Per-team reports for attaching to schedule games, keyed by normalized team name.
    /// ESPN team IDs collide across sports, so names are the safer key.
    static func reportsByTeam(_ injuries: [PlayerInjury]) -> [String: [InjuryReport]] {
        Dictionary(grouping: injuries, by: { normalize($0.teamName) })
            .mapValues { $0.map(\.report) }
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
