//
//  FantasyRosters.swift
//  SportsCalServer
//
//  Every NFL player's position and jersey, from ESPN team rosters. The NFL box score
//  carries neither, and fantasy needs both: positions for the QB/RB/WR filters and
//  verdict floors, and name + team + jersey to match Sleeper players (whose `espn_id`
//  covers about a quarter of active players) to ESPN athlete IDs.
//
//  `FantasyJob` refreshes the Redis copy daily (33 ESPN requests); readers keep an
//  in-process copy for ten minutes.
//

import Foundation
import SportsCalModel
import Redis
import Vapor

struct FantasyRosterSet: Codable, Sendable {
    struct Entry: Codable, Sendable, Equatable {
        var athleteID: String
        var name: String
        var position: String?
        var jersey: String?
        var teamID: String
        var teamAbbreviation: String?
    }

    var updated: Date
    var athletes: [String: Entry]
    /// ESPN abbreviation → ESPN team ID ("DET" → "8").
    var teams: [String: String]

    static let empty = FantasyRosterSet(updated: .distantPast, athletes: [:], teams: [:])

    /// Lines with positions filled where the box score had none. Rosters say "PK" for
    /// kickers and "OT"/"G"/… for linemen; fantasy says "K".
    func fillPositions(_ lines: [FantasyPlayerLine]) -> [FantasyPlayerLine] {
        lines.map { line in
            guard line.position == nil || line.position == "PK", !line.isDST else { return line }
            var line = line
            let position = athletes[line.athleteID]?.position ?? line.position
            line.position = position == "PK" ? "K" : position
            if line.jersey == nil { line.jersey = athletes[line.athleteID]?.jersey }
            return line
        }
    }

    /// Normalized name + team → athlete IDs, for matching other providers' players.
    func index() -> [String: [Entry]] {
        var out: [String: [Entry]] = [:]
        for entry in athletes.values {
            out[FantasyStatLines.normalized(entry.name), default: []].append(entry)
        }
        return out
    }
}

actor FantasyRosters {
    static let shared = FantasyRosters()

    private var cache: [SportType: (set: FantasyRosterSet, loadedAt: Date)] = [:]
    private static let memorySeconds: TimeInterval = 600

    func current(app: Application, sport: SportType, isDebug: Bool) async -> FantasyRosterSet {
        if let hit = cache[sport], Date().timeIntervalSince(hit.loadedAt) < Self.memorySeconds {
            return hit.set
        }
        let key = Self.key(sport: sport, isDebug: isDebug)
        let stored = try? await app.redis.get(key, asJSON: FantasyRosterSet.self)
        let set = stored ?? cache[sport]?.set ?? .empty
        cache[sport] = (set, Date())
        return set
    }

    func store(_ set: FantasyRosterSet, sport: SportType) {
        cache[sport] = (set, Date())
    }

    static func key(sport: SportType, isDebug: Bool) -> RedisKey {
        FantasyService.redisKey("Rosters-\(sport.rawValue)", isDebug: isDebug)
    }

    // MARK: Refresh

    private struct TeamsResponse: Decodable {
        struct Sport: Decodable { var leagues: [League]? }
        struct League: Decodable { var teams: [TeamEntry]? }
        struct TeamEntry: Decodable { var team: Team? }
        struct Team: Decodable { var id: String?; var abbreviation: String? }
        var sports: [Sport]?
    }

    /// Fetches every team's roster from ESPN. Keeps the previous copy's players for any
    /// team whose roster fetch failed.
    static func refresh(app: Application, sport: SportType, isDebug: Bool) async throws -> FantasyRosterSet {
        guard let path = FantasyService.espnPath(for: sport) else { return .empty }
        let base = "https://site.api.espn.com/apis/site/v2/sports/\(path.sport)/\(path.league)/teams"
        let teamsResponse = try await ESPNNetworking.performGet(app.client, URI(string: base))
        let teams = (try teamsResponse.content.decode(TeamsResponse.self)).sports?.first?.leagues?.first?.teams?
            .compactMap(\.team) ?? []
        guard !teams.isEmpty else { throw Abort(.badGateway, reason: "ESPN returned no teams") }
        let previous = await shared.current(app: app, sport: sport, isDebug: isDebug)

        var athletes: [String: FantasyRosterSet.Entry] = [:]
        var abbreviations: [String: String] = [:]
        for team in teams {
            guard let teamID = team.id else { continue }
            if let abbr = team.abbreviation { abbreviations[abbr] = teamID }
            do {
                let response = try await ESPNNetworking.performGet(app.client, URI(string: "\(base)/\(teamID)/roster"))
                let roster = try response.content.decode(RosterResponse.self)
                for group in roster.athletes ?? [] {
                    for athlete in group.items ?? [] {
                        guard let id = athlete.id, let name = athlete.fullName ?? athlete.displayName else { continue }
                        athletes[id] = .init(athleteID: id, name: name, position: athlete.position?.abbreviation,
                                             jersey: athlete.jersey, teamID: teamID, teamAbbreviation: team.abbreviation)
                    }
                }
            } catch {
                FantasyService.logger.warning("Roster fetch failed", metadata: ["team": "\(teamID)", "error": "\(error)"])
                for entry in previous.athletes.values where entry.teamID == teamID { athletes[entry.athleteID] = entry }
            }
            // ESPN is the shared budget for every job; a roster sweep can wait.
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        let set = FantasyRosterSet(updated: Date(), athletes: athletes, teams: abbreviations)
        try await app.redis.set(key(sport: sport, isDebug: isDebug), toJSON: set)
        await shared.store(set, sport: sport)
        return set
    }

    /// Just the fields read here; the shared `ESPNNetworking.RosterResponse` maps to
    /// World Cup squad players.
    private struct RosterResponse: Decodable {
        struct Group: Decodable { var items: [Athlete]? }
        struct Athlete: Decodable {
            var id: String?
            var fullName: String?
            var displayName: String?
            var jersey: String?
            var position: Position?
        }
        struct Position: Decodable { var abbreviation: String? }
        var athletes: [Group]?
    }
}
