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
                if league == .ncaaMBBTournament { continue }
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
        let mappingKey: RedisKey = context.application.environment == .development ? "debug-ESPN-ID-Map" : "ESPN-ID-Map"
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

        for (league, teamResponse) in espnTeamsByLeague {
            let bucket = league.sportBucket
            for espnTeam in teamResponse.teams ?? [] {
                let espnLogo = espnTeam.logos?.first?.href
                let espnAbbrev = espnTeam.abbreviation

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

                // Fallback: check if any TheSportsDB team name ends with the ESPN team name
                if matchedID == nil, let espnName = espnTeam.name?.lowercased(), espnName.count > 3 {
                    let matches = nameToID.filter { (key, _) in key.hasSuffix(espnName) }
                    if matches.count == 1 {
                        matchedID = matches.first?.value
                    }
                }

                if let matchedID = matchedID, let existingTeam = teamsByID[matchedID] {
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
                    teamsByID[matchedID] = Team(
                        idTeam: existingTeam.idTeam,
                        strTeam: existingTeam.strTeam,
                        strTeamShort: Team.canonicalAbbreviationOverrides[existingTeam.idTeam ?? ""] ?? espnAbbrev ?? existingTeam.strTeamShort,
                        strAlternate: combinedAlternate,
                        strTeamBadge: espnLogo ?? existingTeam.strTeamBadge
                    )

                    // Map sport-scoped ESPN ID → TheSportsDB ID
                    if let espnID = espnTeam.id {
                        espnToTSDB["\(bucket):\(espnID)"] = matchedID
                    }
                }
            }
        }

        return (Array(teamsByID.values), espnToTSDB)
    }
}
