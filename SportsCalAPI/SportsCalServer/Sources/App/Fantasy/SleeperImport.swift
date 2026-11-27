//
//  SleeperImport.swift
//  SportsCalServer
//
//  Imports a Sleeper league (public API, no auth): its scoring and every roster in
//  ESPN athlete IDs. Runs here rather than on the phone because mapping Sleeper's
//  player IDs needs Sleeper's 14MB player database, cached here as a slim index.
//
//  Matching, in order: Sleeper's own `espn_id`; else name + team against ESPN
//  rosters (jersey breaks ties); defenses by team abbreviation.
//

import Foundation
import SportsCalModel
import Redis
import Vapor

enum SleeperImport {
    static let base = "https://api.sleeper.app/v1"

    // MARK: Sleeper API shapes

    struct User: Decodable {
        var user_id: String
        var username: String?
        var display_name: String?
        var avatar: String?
    }

    struct League: Decodable {
        var league_id: String
        var name: String?
        var season: String?
        var total_rosters: Int?
        var avatar: String?
        var scoring_settings: [String: Double]?
    }

    struct Roster: Decodable {
        var roster_id: Int
        var owner_id: String?
        var players: [String]?
        var starters: [String]?
    }

    struct LeagueUser: Decodable {
        var user_id: String
        var display_name: String?
        var metadata: Metadata?
        struct Metadata: Decodable { var team_name: String? }
    }

    struct State: Decodable { var league_season: String?; var season: String? }

    struct Player: Codable, Sendable {
        var name: String
        var team: String?
        var number: String?
        var position: String?
        var espnID: String?
    }

    private struct RawPlayer: Decodable {
        var full_name: String?
        var first_name: String?
        var last_name: String?
        var team: String?
        var number: LossyString?
        var position: String?
        var espn_id: LossyString?
    }

    /// Sleeper sends some numbers as strings and some as numbers.
    private struct LossyString: Decodable {
        var value: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { value = s }
            else if let i = try? c.decode(Int.self) { value = String(i) }
            else { value = nil }
        }
    }

    // MARK: Requests

    static func get<T: Decodable>(_ path: String, as type: T.Type, client: Client) async throws -> T {
        let response = try await client.get(URI(string: base + path)) { request in
            request.headers.replaceOrAdd(name: .userAgent, value: "SportsCalServer/1.0")
        }
        guard response.status == .ok else {
            throw Abort(response.status == .notFound ? .notFound : .badGateway, reason: "Sleeper returned \(response.status.code)")
        }
        return try response.content.decode(T.self)
    }

    static func currentSeason(client: Client) async -> Int {
        let state = try? await get("/state/nfl", as: State.self, client: client)
        return (state?.league_season ?? state?.season).flatMap(Int.init) ?? Calendar.current.component(.year, from: Date())
    }

    /// Usernames are letters, digits and underscores; never let one reshape the path.
    static func isValidUsername(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 40 && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 30 && id.allSatisfy(\.isNumber)
    }

    static func user(username: String, app: Application) async throws -> FantasySleeperUser {
        guard isValidUsername(username) else { throw Abort(.badRequest, reason: "Invalid username") }
        let user = try await get("/user/\(username)", as: User?.self, client: app.client)
        guard let user else { throw Abort(.notFound, reason: "No Sleeper user \(username)") }
        let season = await currentSeason(client: app.client)
        let leagues = try await get("/user/\(user.user_id)/leagues/nfl/\(season)", as: [League].self, client: app.client)
        return FantasySleeperUser(
            userID: user.user_id,
            displayName: user.display_name ?? user.username ?? username,
            avatar: user.avatar,
            leagues: leagues.map {
                FantasyLeagueSummary(id: $0.league_id, name: $0.name ?? "League", season: $0.season.flatMap(Int.init) ?? season,
                                     teamCount: $0.total_rosters, avatar: $0.avatar)
            }
        )
    }

    static func league(id: String, userID: String?, app: Application, isDebug: Bool) async throws -> FantasyLeague {
        guard isValidID(id), userID.map(isValidID) ?? true else { throw Abort(.badRequest) }
        async let leagueTask = get("/league/\(id)", as: League?.self, client: app.client)
        async let rostersTask = get("/league/\(id)/rosters", as: [Roster].self, client: app.client)
        async let usersTask = get("/league/\(id)/users", as: [LeagueUser].self, client: app.client)
        guard let league = try await leagueTask else { throw Abort(.notFound, reason: "No Sleeper league \(id)") }
        let rosters = try await rostersTask
        let users = try await usersTask

        let players = try await playerIndex(app: app, isDebug: isDebug)
        let espn = await FantasyRosters.shared.current(app: app, sport: .nfl, isDebug: isDebug)
        let matcher = Matcher(players: players, rosters: espn)

        let name = league.name ?? "Sleeper League"
        let leagueID = "sleeper.\(id)"
        let (scoring, unsupported) = SleeperScoring.scoring(settings: league.scoring_settings ?? [:], id: leagueID, name: name)
        let usersByID = Dictionary(users.map { ($0.user_id, $0) }, uniquingKeysWith: { first, _ in first })

        let teams: [FantasyLeague.Team] = rosters.map { roster in
            let owner = roster.owner_id.flatMap { usersByID[$0] }
            var unmatched: [String] = []
            let athleteIDs = (roster.players ?? []).compactMap { sleeperID -> String? in
                if let id = matcher.espnID(sleeperID: sleeperID) { return id }
                unmatched.append(matcher.describe(sleeperID: sleeperID))
                return nil
            }
            let starters = (roster.starters ?? []).compactMap { matcher.espnID(sleeperID: $0) }
            return FantasyLeague.Team(
                id: String(roster.roster_id),
                name: owner?.metadata?.team_name ?? owner?.display_name ?? "Team \(roster.roster_id)",
                ownerName: owner?.display_name,
                athleteIDs: athleteIDs,
                starterIDs: starters,
                unmatched: unmatched.isEmpty ? nil : unmatched
            )
        }
        let myTeam = userID.flatMap { userID in rosters.first { $0.owner_id == userID } }
        return FantasyLeague(
            id: leagueID, provider: .sleeper, providerLeagueID: id, name: name,
            season: league.season.flatMap(Int.init) ?? Calendar.current.component(.year, from: Date()),
            sport: .nfl, scoring: scoring, teams: teams, myTeamID: myTeam.map { String($0.roster_id) },
            unsupportedRules: unsupported, importedAt: Date()
        )
    }

    // MARK: Player index

    private static let indexSeconds = 24 * 60 * 60
    private static let indexLoader = SleeperIndexLoader()

    /// Sleeper player ID → the fields matching needs, for fantasy positions only.
    static func playerIndex(app: Application, isDebug: Bool) async throws -> [String: Player] {
        try await indexLoader.load {
            let key = FantasyService.redisKey("Sleeper-Players", isDebug: isDebug)
            if let cached = try? await app.redis.get(key, asJSON: [String: Player].self), !cached.isEmpty {
                return cached
            }
            let response = try await app.client.get(URI(string: base + "/players/nfl")) { request in
                request.headers.replaceOrAdd(name: .userAgent, value: "SportsCalServer/1.0")
            }
            guard response.status == .ok, let body = response.body else { throw Abort(.badGateway, reason: "Sleeper players unavailable") }
            let raw = try JSONDecoder().decode([String: RawPlayer].self, from: Data(body.readableBytesView))
            let fantasyPositions: Set<String> = ["QB", "RB", "WR", "TE", "K", "DEF"]
            var slim: [String: Player] = [:]
            for (id, player) in raw {
                guard let position = player.position, fantasyPositions.contains(position) else { continue }
                let name = player.full_name ?? [player.first_name, player.last_name].compactMap { $0 }.joined(separator: " ")
                slim[id] = Player(name: name, team: player.team, number: player.number?.value,
                                  position: position, espnID: player.espn_id?.value)
            }
            try? await app.redis.setex(key, toJSON: slim, expirationInSeconds: indexSeconds)
            return slim
        }
    }

    // MARK: Matching

    struct Matcher {
        let players: [String: Player]
        let rosters: FantasyRosterSet
        let byName: [String: [FantasyRosterSet.Entry]]

        init(players: [String: Player], rosters: FantasyRosterSet) {
            self.players = players
            self.rosters = rosters
            byName = rosters.index()
        }

        /// Sleeper abbreviations that differ from ESPN's.
        static let teamAliases = ["WAS": "WSH", "JAC": "JAX", "LA": "LAR", "OAK": "LV", "SD": "LAC"]

        static func espnAbbreviation(_ sleeper: String) -> String { teamAliases[sleeper] ?? sleeper }

        func espnID(sleeperID: String) -> String? {
            // Defenses are keyed by team abbreviation ("DET").
            if sleeperID.allSatisfy(\.isLetter) {
                let abbr = Self.espnAbbreviation(sleeperID.uppercased())
                return rosters.teams[abbr].map(FantasyStatLines.dstAthleteID(teamID:))
            }
            guard let player = players[sleeperID] else { return nil }
            if player.position == "DEF", let team = player.team {
                return rosters.teams[Self.espnAbbreviation(team)].map(FantasyStatLines.dstAthleteID(teamID:))
            }
            if let espnID = player.espnID, !espnID.isEmpty { return espnID }
            let candidates = byName[FantasyStatLines.normalized(player.name)] ?? []
            if let team = player.team.map(Self.espnAbbreviation) {
                let onTeam = candidates.filter { $0.teamAbbreviation == team }
                if onTeam.count == 1 { return onTeam[0].athleteID }
                if let number = player.number, let byJersey = onTeam.first(where: { $0.jersey == number }) {
                    return byJersey.athleteID
                }
            }
            // A free agent or a traded player whose roster hasn't refreshed: only an
            // unambiguous name will do.
            return candidates.count == 1 ? candidates[0].athleteID : nil
        }

        func describe(sleeperID: String) -> String {
            guard let player = players[sleeperID] else { return "Sleeper player \(sleeperID)" }
            let detail = [player.position, player.team].compactMap { $0 }.joined(separator: ", ")
            return detail.isEmpty ? player.name : "\(player.name) (\(detail))"
        }
    }
}

/// One download of the Sleeper player database at a time: two imports at once must
/// not both pull 14MB.
actor SleeperIndexLoader {
    private var inFlight: Task<[String: SleeperImport.Player], Error>?
    private var memory: (index: [String: SleeperImport.Player], loadedAt: Date)?

    func load(_ fetch: @escaping @Sendable () async throws -> [String: SleeperImport.Player]) async throws -> [String: SleeperImport.Player] {
        if let memory, Date().timeIntervalSince(memory.loadedAt) < 3600 { return memory.index }
        if let inFlight { return try await inFlight.value }
        let task = Task { try await fetch() }
        inFlight = task
        defer { inFlight = nil }
        let index = try await task.value
        memory = (index, Date())
        return index
    }
}
