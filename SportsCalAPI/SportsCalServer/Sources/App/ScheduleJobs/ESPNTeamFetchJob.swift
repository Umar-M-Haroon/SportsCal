//
//  File.swift
//  
//
//  Created by Umar Haroon on 2/23/23.
//

import Foundation
import Queues
import RediStack
import SportsCalModel
import Logging

struct ESPNTeamFetchJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.espn-teams")

    func run(context: Queues.QueueContext) async throws {
        Self.logger.info("ESPNTeamFetchJob starting")
        let endpoint = RedisEndpoint.SportsDB.teams.getValue(isDebug: context.application.environment == .development)
        guard let currentTeams = try await context.application.redis.get(endpoint, asJSON: [Team].self), !currentTeams.isEmpty else {
            Self.logger.warning("No current teams found, skipping ESPNTeamFetchJob")
            return
        }

        let espnTeamsDict = try await withThrowingTaskGroup(of: [Leagues: TeamResponse].self) { group in
            var allTeams: [Leagues: TeamResponse] = [:]
            for league in Leagues.allCases {
                // Skip NCAA — college team names collide with pro teams
                // (e.g. "Islanders" matching "New York Islanders") and would
                // overwrite logos/abbreviations with wrong data
                // College football teams aren't in the teams payload at all (see DBUpdateJob).
                if league == .ncaaMBBTournament || league == .ncaaf { continue }
                // Leagues not sourced from ESPN (NASCAR) have no teams endpoint; asking
                // throws, and one throw fails this whole group.
                if league.espnSlug == nil { continue }
                group.addTask {
                    [league : try await Integrator.getTeam(league: league, client: context.application.client)]
                }
            }
            for try await teams in group {
                allTeams.merge(teams) { team1, team2 in
                    team1
                }
            }
            return allTeams
        }

        try await context.application.redis.set(RedisEndpoint.ESPN.teams.getValue(isDebug: context.application.environment == .development), toJSON: espnTeamsDict)
        let (finalTeams, espnToTSDBMapping) = returnUpdatedTeams(teams: currentTeams, espnTeamsByLeague: espnTeamsDict)

        // Store ESPN-ID → TheSportsDB-ID mapping for live game ID translation
        let mappingKey = RedisEndpoint.ESPN.espnIDMap.getValue(isDebug: context.application.environment == .development)
        try await context.application.redis.set(mappingKey, toJSON: espnToTSDBMapping)
        let teamsWithLogos = finalTeams.filter({ $0.strTeamBadge != nil }).count
        let previousLogos = currentTeams.filter({ $0.strTeamBadge != nil }).count
        let newLogos = teamsWithLogos - previousLogos

        Self.logger.info("ESPNTeamFetchJob complete", metadata: [
            "totalTeams": "\(finalTeams.count)",
            "baseTeams": "\(currentTeams.count)",
            "idMappings": "\(espnToTSDBMapping.count)",
            "teamsWithLogos": "\(teamsWithLogos)",
            "newLogos": "\(newLogos)"
        ])

        try await context.application.redis.set(RedisEndpoint.teams.getValue(isDebug: context.application.environment == .development), toJSON: finalTeams)
    }
    
    /// Returns (enriched teams, sport-scoped ESPN-ID → TheSportsDB-ID mapping).
    /// Keys in the ID map are prefixed with the sport bucket (e.g. "nba:18") to
    /// prevent cross-sport collisions where ESPN reuses the same numeric team ID
    /// across different sports (NBA ID 18 ≠ NHL ID 18).
    func returnUpdatedTeams(teams: [Team], espnTeamsByLeague: [Leagues: TeamResponse]) -> ([Team], [String: String]) {
        // Use idTeam as the primary key to avoid duplicates
        var teamsByID: [String: Team] = [:]

        // Build name → idTeam lookup for matching ESPN teams (case-insensitive)
        var nameToID: [String: String] = [:]

        for team in teams {
            guard let idTeam = team.idTeam else { continue }
            teamsByID[idTeam] = team

            // Index by primary name
            if let strTeam = team.strTeam {
                let lower = strTeam.lowercased()
                nameToID[lower] = idTeam
                let normalized = lower
                    .replacingOccurrences(of: "é", with: "e")
                    .replacingOccurrences(of: "á", with: "a")
                if normalized != lower {
                    nameToID[normalized] = idTeam
                }
            }

            // Index by each alternate name
            if let alternate = team.strAlternate {
                for altName in alternate.components(separatedBy: ", ") {
                    let lower = altName.lowercased()
                    nameToID[lower] = idTeam
                    let normalized = lower
                        .replacingOccurrences(of: "é", with: "e")
                        .replacingOccurrences(of: "á", with: "a")
                    if normalized != lower {
                        nameToID[normalized] = idTeam
                    }
                }
            }
        }

        // Common city abbreviation expansions for matching
        let cityExpansions: [String: String] = [
            "la ": "los angeles ",
            "ny ": "new york ",
            "nyrb": "new york red bulls",
            "nyc ": "new york city ",
            "dc ": "washington ",
            "d.c. ": "washington ",
            "st ": "saint ",
            "st. ": "saint ",
            "fc ": "football club ",
        ]

        // Build ESPN-ID → TheSportsDB-ID mapping keyed by sport bucket to prevent
        // cross-sport ID collisions (e.g. "nba:18" and "nhl:18" are different teams).
        var espnToTSDB: [String: String] = [:]

        // Match every ESPN team first, then apply exact-name matches before the loose
        // suffix fallback. A fallback may never take a team another league matched by
        // name: WNBA "Dallas Wings" (name "Wings") used to suffix-match "Detroit Red
        // Wings" and, depending on dictionary order, overwrite the Red Wings' ESPN
        // abbreviation (DAL) and logo with the Wings'.
        var matches: [(bucket: String, espnTeam: ESPNTeam, matchedID: String, exact: Bool)] = []

        // Leagues in a stable order so a tie between two exact matches is deterministic.
        for (league, teamResponse) in espnTeamsByLeague.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let bucket = league.sportBucket
            for espnTeam in teamResponse.teams ?? [] {
                // Try to find a matching TheSportsDB team by any ESPN name field
                var matchedID: String?
                let nameCandidates = [espnTeam.displayName, espnTeam.shortDisplayName, espnTeam.name, espnTeam.nickname].compactMap({ $0 })

                for candidate in nameCandidates {
                    let lower = candidate.lowercased()
                    if let id = nameToID[lower] {
                        matchedID = id
                        break
                    }
                    let normalized = lower
                        .replacingOccurrences(of: "é", with: "e")
                        .replacingOccurrences(of: "á", with: "a")
                    if normalized != lower, let id = nameToID[normalized] {
                        matchedID = id
                        break
                    }
                    // Try expanding city abbreviations (e.g., "LA Clippers" → "Los Angeles Clippers")
                    for (abbrev, expansion) in cityExpansions {
                        if lower.hasPrefix(abbrev) {
                            let expanded = lower.replacingOccurrences(of: abbrev, with: expansion)
                            if let id = nameToID[expanded] {
                                matchedID = id
                                break
                            }
                        }
                    }
                    if matchedID != nil { break }
                }

                if let matchedID {
                    matches.append((bucket, espnTeam, matchedID, true))
                } else if let fallbackID = Self.suffixFallbackMatch(espnTeam: espnTeam, nameToID: nameToID) {
                    matches.append((bucket, espnTeam, fallbackID, false))
                }
            }
        }

        let exactIDs = Set(matches.filter(\.exact).map(\.matchedID))
        for match in matches.filter(\.exact) + matches.filter({ !$0.exact }) {
            if !match.exact && exactIDs.contains(match.matchedID) { continue }
            let espnTeam = match.espnTeam
            guard let existingTeam = teamsByID[match.matchedID] else { continue }

            // Build alternate names: combine existing alternate with ESPN displayName if different from strTeam
            var alternates: [String] = []
            if let existing = existingTeam.strAlternate {
                alternates.append(contentsOf: existing.components(separatedBy: ", "))
            }
            if let espnDisplay = espnTeam.displayName,
               espnDisplay != existingTeam.strTeam,
               !alternates.contains(espnDisplay) {
                alternates.append(espnDisplay)
            }
            let combinedAlternate = alternates.isEmpty ? nil : alternates.joined(separator: ", ")

            // Enrich existing team with ESPN logo (preferred), abbreviation, and alternate names
            teamsByID[match.matchedID] = Team(
                idTeam: existingTeam.idTeam,
                strTeam: existingTeam.strTeam,
                strTeamShort: Team.canonicalAbbreviationOverrides[existingTeam.idTeam ?? ""] ?? espnTeam.abbreviation ?? existingTeam.strTeamShort,
                strAlternate: combinedAlternate,
                strTeamBadge: espnTeam.logos?.first?.href ?? existingTeam.strTeamBadge
            )

            // Map sport-scoped ESPN ID → TheSportsDB ID
            if let espnID = espnTeam.id {
                espnToTSDB["\(match.bucket):\(espnID)"] = match.matchedID
            }
        }

        return (Array(teamsByID.values), espnToTSDB)
    }

    /// Loose match for an ESPN team no name field matched exactly: the one TheSportsDB
    /// team whose name ends with ESPN's team name ("Alavés" → "Deportivo Alavés")
    /// and that also names ESPN's city. Without the city check a WNBA team claimed a
    /// same-nickname team in another sport — "Dallas Wings" took "Detroit Red Wings",
    /// "Portland Fire" took MLS "Chicago Fire" (abbreviation POR, Portland's logo).
    static func suffixFallbackMatch(espnTeam: ESPNTeam, nameToID: [String: String]) -> String? {
        guard let espnName = espnTeam.name?.lowercased(), espnName.count > 3 else { return nil }
        // City = displayName minus the team name ("Dallas Wings" − "Wings" → "dallas").
        var city = ""
        if let display = espnTeam.displayName?.lowercased(), display.hasSuffix(espnName) {
            city = String(display.dropLast(espnName.count)).trimmingCharacters(in: .whitespaces)
        }
        let ids = Set(nameToID.filter { key, _ in
            key.hasSuffix(espnName) && (city.isEmpty || key.contains(city))
        }.values)
        return ids.count == 1 ? ids.first : nil
    }
}
