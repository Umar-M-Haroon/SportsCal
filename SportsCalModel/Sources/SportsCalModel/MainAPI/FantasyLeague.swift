//
//  FantasyLeague.swift
//  SportsCalModel
//
//  A fantasy league imported from Sleeper or ESPN: its scoring, mapped onto our stat
//  keys, and every roster in ESPN athlete IDs (the IDs our box scores carry), so
//  "my team" is a filter over the same `FantasySlate` everything else reads.
//
//  Sleeper imports run on the server (its player IDs need the 14MB Sleeper player
//  database to map). ESPN imports run on the device: ESPN fantasy player IDs already
//  are ESPN athlete IDs, and a private league's cookies never leave the phone.
//

import Foundation

public struct FantasyLeague: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Provider: String, Codable, Sendable, CaseIterable {
        case sleeper, espn

        public var displayName: String {
            switch self {
            case .sleeper: return "Sleeper"
            case .espn: return "ESPN"
            }
        }
    }

    /// "sleeper.1180234" / "espn.336358".
    public var id: String
    public var provider: Provider
    public var providerLeagueID: String
    public var name: String
    public var season: Int
    public var sport: SportType
    public var scoring: FantasyScoring
    public var teams: [Team]
    /// The user's own team, when the import knew who they are (Sleeper username) or
    /// they picked one.
    public var myTeamID: String?
    /// League scoring rules we can't apply ("bonus_rec_te 0.5"), so the UI can say so.
    public var unsupportedRules: [String]
    public var importedAt: Date

    public struct Team: Codable, Equatable, Hashable, Sendable, Identifiable {
        public var id: String
        /// "Gibbs Me A Break".
        public var name: String
        public var ownerName: String?
        /// The whole roster, in ESPN athlete IDs (`dst-{teamID}` for a defense).
        public var athleteIDs: [String]
        /// This week's starters, where the provider says.
        public var starterIDs: [String]?
        /// Rostered players we couldn't find an ESPN ID for: "Caleb Williams (QB, CHI)".
        public var unmatched: [String]?

        public init(id: String, name: String, ownerName: String? = nil, athleteIDs: [String],
                    starterIDs: [String]? = nil, unmatched: [String]? = nil) {
            self.id = id
            self.name = name
            self.ownerName = ownerName
            self.athleteIDs = athleteIDs
            self.starterIDs = starterIDs
            self.unmatched = unmatched
        }
    }

    public init(id: String, provider: Provider, providerLeagueID: String, name: String, season: Int,
                sport: SportType, scoring: FantasyScoring, teams: [Team], myTeamID: String? = nil,
                unsupportedRules: [String] = [], importedAt: Date) {
        self.id = id
        self.provider = provider
        self.providerLeagueID = providerLeagueID
        self.name = name
        self.season = season
        self.sport = sport
        self.scoring = scoring
        self.teams = teams
        self.myTeamID = myTeamID
        self.unsupportedRules = unsupportedRules
        self.importedAt = importedAt
    }

    public var myTeam: Team? { myTeamID.flatMap { id in teams.first { $0.id == id } } }
}

/// A league a Sleeper user is in, before importing it.
public struct FantasyLeagueSummary: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var season: Int
    public var teamCount: Int?
    public var avatar: String?

    public init(id: String, name: String, season: Int, teamCount: Int? = nil, avatar: String? = nil) {
        self.id = id
        self.name = name
        self.season = season
        self.teamCount = teamCount
        self.avatar = avatar
    }
}

// MARK: - Sleeper scoring

public enum SleeperScoring {
    typealias K = FantasyStatKey.NFL

    /// Sleeper `scoring_settings` key → our stat key, for per-unit weights.
    static let weights: [String: String] = [
        "pass_yd": K.passingYards, "pass_td": K.passingTouchdowns, "pass_int": K.interceptionsThrown,
        "pass_cmp": K.completions, "pass_att": K.passingAttempts, "pass_sack": K.sacksTaken,
        "pass_2pt": K.twoPointConversions, "rush_2pt": K.twoPointConversions, "rec_2pt": K.twoPointConversions,
        "rush_yd": K.rushingYards, "rush_td": K.rushingTouchdowns, "rush_att": K.rushingAttempts,
        "rec": K.receptions, "rec_yd": K.receivingYards, "rec_td": K.receivingTouchdowns, "rec_tgt": K.targets,
        "fum_lost": K.fumblesLost, "fum": K.fumbles,
        "kr_td": K.kickReturnTouchdowns, "pr_td": K.puntReturnTouchdowns,
        "st_td": K.kickReturnTouchdowns,
        "fgm_30_39": K.fieldGoals0to39, "fgm_40_49": K.fieldGoals40to49, "fgm_50p": K.fieldGoals50plus,
        "fgm_50_59": K.fieldGoals50plus, "fgmiss": K.fieldGoalsMissed, "xpm": K.extraPointsMade, "xpmiss": K.extraPointsMissed,
        "sack": K.dstSacks, "int": K.dstInterceptions, "fum_rec": K.dstFumblesRecovered, "def_td": K.dstTouchdowns,
        "def_st_td": K.dstTouchdowns, "safe": K.dstSafeties, "blk_kick": K.dstBlockedKicks,
    ]

    /// Keys folded into one of ours that a league almost always sets the same (Sleeper
    /// splits field goals at 19/29/39; we bucket 0–39). Not reported as unsupported.
    static let folded: Set<String> = ["fgm_0_19", "fgm_20_29", "fgm_60p", "fgmiss_0_19", "fgmiss_20_29",
                                      "fgmiss_30_39", "fgmiss_40_49", "fgmiss_50p", "st_fum_rec", "def_st_fum_rec",
                                      "st_ff", "def_st_ff", "ff", "fum_rec_td"]

    static let pointsAllowed: [(key: String, min: Double, max: Double?)] = [
        ("pts_allow_0", 0, 1), ("pts_allow_1_6", 1, 7), ("pts_allow_7_13", 7, 14), ("pts_allow_14_20", 14, 21),
        ("pts_allow_21_27", 21, 28), ("pts_allow_28_34", 28, 35), ("pts_allow_35p", 35, nil),
    ]

    static let bonuses: [(key: String, stat: String, min: Double)] = [
        ("bonus_pass_yd_300", K.passingYards, 300), ("bonus_pass_yd_400", K.passingYards, 400),
        ("bonus_rush_yd_100", K.rushingYards, 100), ("bonus_rush_yd_200", K.rushingYards, 200),
        ("bonus_rec_yd_100", K.receivingYards, 100), ("bonus_rec_yd_200", K.receivingYards, 200),
    ]

    /// `scoring_settings` as a scoring, and the keys with points we couldn't use.
    public static func scoring(
        settings: [String: Double], id: String, name: String
    ) -> (scoring: FantasyScoring, unsupported: [String]) {
        var weights: [String: Double] = [:]
        var rules: [FantasyScoring.Rule] = []
        var unsupported: [String] = []
        let tierKeys = Set(pointsAllowed.map(\.key))
        let bonusKeys = Set(bonuses.map(\.key))
        for (key, points) in settings where points != 0 {
            if let stat = Self.weights[key] {
                // Three 2-pt keys share our one stat; Sleeper sets them alike.
                weights[stat] = weights[stat] ?? points
            } else if !tierKeys.contains(key), !bonusKeys.contains(key), !folded.contains(key) {
                unsupported.append("\(key) \(FantasyScoring.format(points))")
            }
        }
        for tier in pointsAllowed {
            guard let points = settings[tier.key] else { continue }
            rules.append(.init(stat: K.dstPointsAllowed, min: tier.min, max: tier.max, points: points))
        }
        for bonus in bonuses {
            guard let points = settings[bonus.key], points != 0 else { continue }
            rules.append(.init(stat: bonus.stat, min: bonus.min, points: points))
        }
        let scoring = FantasyScoring(id: id, name: name, sport: .nfl, weights: weights, rules: rules)
        return (scoring, unsupported.sorted())
    }
}

// MARK: - ESPN fantasy (on device)

public enum ESPNFantasy {
    typealias K = FantasyStatKey.NFL

    /// `GET lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{id}?view=mSettings&view=mRoster&view=mTeam`.
    /// Private leagues need the `espn_s2` and `SWID` cookies from a signed-in browser.
    public static func leagueURL(leagueID: String, season: Int) -> URL? {
        guard leagueID.allSatisfy(\.isNumber), !leagueID.isEmpty else { return nil }
        return URL(string: "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/\(season)/segments/0/leagues/\(leagueID)?view=mSettings&view=mRoster&view=mTeam")
    }

    public struct LeagueResponse: Decodable {
        public var id: Int?
        public var seasonId: Int?
        public var settings: Settings?
        public var teams: [TeamEntry]?
        public var members: [Member]?

        public struct Settings: Decodable {
            public var name: String?
            public var scoringSettings: ScoringSettings?
        }
        public struct ScoringSettings: Decodable {
            public var scoringItems: [ScoringItem]?
        }
        public struct ScoringItem: Decodable {
            public var statId: Int
            public var points: Double?
        }
        public struct TeamEntry: Decodable {
            public var id: Int
            public var name: String?
            public var location: String?
            public var nickname: String?
            public var abbrev: String?
            public var owners: [String]?
            public var primaryOwner: String?
            public var roster: Roster?
        }
        public struct Roster: Decodable {
            public var entries: [Entry]?
        }
        public struct Entry: Decodable {
            public var playerId: Int
            /// 20 = bench, 21 = IR; anything else is a starting slot.
            public var lineupSlotId: Int?
            public var playerPoolEntry: PoolEntry?
        }
        public struct PoolEntry: Decodable {
            public var player: Player?
        }
        public struct Player: Decodable {
            public var fullName: String?
        }
        public struct Member: Decodable {
            public var id: String
            public var displayName: String?
            public var firstName: String?
            public var lastName: String?
        }
    }

    /// ESPN fantasy stat ID → our key, per-unit.
    static let weights: [Int: String] = [
        0: K.passingAttempts, 1: K.completions, 3: K.passingYards, 4: K.passingTouchdowns,
        19: K.twoPointConversions, 20: K.interceptionsThrown, 23: K.rushingAttempts, 24: K.rushingYards,
        25: K.rushingTouchdowns, 26: K.twoPointConversions, 42: K.receivingYards, 43: K.receivingTouchdowns,
        44: K.twoPointConversions, 53: K.receptions, 58: K.targets, 64: K.sacksTaken, 68: K.fumbles,
        72: K.fumblesLost, 74: K.fieldGoals50plus, 77: K.fieldGoals40to49, 80: K.fieldGoals0to39,
        85: K.fieldGoalsMissed, 86: K.extraPointsMade, 88: K.extraPointsMissed, 95: K.dstInterceptions,
        96: K.dstFumblesRecovered, 97: K.dstBlockedKicks, 98: K.dstSafeties, 99: K.dstSacks,
        101: K.kickReturnTouchdowns, 102: K.puntReturnTouchdowns, 198: K.fieldGoals50plus,
    ]

    /// "Every N yards" stat IDs → (key, N): scored per yard at points / N.
    static let perYards: [Int: (String, Double)] = [
        5: (K.passingYards, 5), 6: (K.passingYards, 10), 7: (K.passingYards, 20), 8: (K.passingYards, 25),
        27: (K.rushingYards, 5), 28: (K.rushingYards, 10), 29: (K.rushingYards, 20), 30: (K.rushingYards, 25),
        45: (K.receivingYards, 5), 46: (K.receivingYards, 10), 47: (K.receivingYards, 20), 48: (K.receivingYards, 25),
    ]

    /// Defensive / return TDs that all land on our one `dst.touchdowns`.
    static let dstTouchdownIDs: Set<Int> = [93, 94, 103, 104]

    static let pointsAllowed: [Int: (Double, Double?)] = [
        89: (0, 1), 90: (1, 7), 91: (7, 14), 92: (14, 18), 121: (18, 22), 122: (22, 28),
        123: (28, 35), 124: (35, 46), 125: (46, nil),
    ]

    static let bonuses: [Int: (String, Double)] = [
        17: (K.passingYards, 300), 18: (K.passingYards, 400), 37: (K.rushingYards, 100),
        38: (K.rushingYards, 200), 56: (K.receivingYards, 100), 57: (K.receivingYards, 200),
    ]

    public static func scoring(items: [LeagueResponse.ScoringItem], id: String, name: String)
        -> (scoring: FantasyScoring, unsupported: [String]) {
        var weights: [String: Double] = [:]
        var rules: [FantasyScoring.Rule] = []
        var unsupported: [String] = []
        for item in items {
            guard let points = item.points, points != 0 else { continue }
            if let key = Self.weights[item.statId] {
                weights[key] = weights[key] ?? points
            } else if let (key, every) = perYards[item.statId] {
                weights[key] = (weights[key] ?? 0) + points / every
            } else if dstTouchdownIDs.contains(item.statId) {
                weights[K.dstTouchdowns] = weights[K.dstTouchdowns] ?? points
            } else if let (min, max) = pointsAllowed[item.statId] {
                rules.append(.init(stat: K.dstPointsAllowed, min: min, max: max, points: points))
            } else if let (stat, min) = bonuses[item.statId] {
                rules.append(.init(stat: stat, min: min, points: points))
            } else {
                unsupported.append("ESPN stat \(item.statId) \(FantasyScoring.format(points))")
            }
        }
        return (FantasyScoring(id: id, name: name, sport: .nfl, weights: weights, rules: rules), unsupported)
    }

    /// ESPN fantasy D/ST player IDs are `-16000 - proTeamId`, and pro team IDs match
    /// ESPN's own team IDs.
    public static func athleteID(playerID: Int) -> String {
        playerID < 0 ? FantasyStatLines.dstAthleteID(teamID: String(-16000 - playerID)) : String(playerID)
    }

    /// Bench and IR slots; every other slot starts.
    static let benchSlots: Set<Int> = [20, 21]

    public static func league(
        from response: LeagueResponse, leagueID: String, season: Int, swid: String?, importedAt: Date = Date()
    ) -> FantasyLeague {
        let name = response.settings?.name ?? "ESPN League \(leagueID)"
        let id = "espn.\(leagueID)"
        let (scoring, unsupported) = scoring(items: response.settings?.scoringSettings?.scoringItems ?? [], id: id, name: name)
        let members = Dictionary((response.members ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let teams: [FantasyLeague.Team] = (response.teams ?? []).map { entry in
            let roster = entry.roster?.entries ?? []
            let owner = (entry.primaryOwner ?? entry.owners?.first).flatMap { members[$0] }
            let teamName = entry.name ?? [entry.location, entry.nickname].compactMap { $0 }.joined(separator: " ")
            return FantasyLeague.Team(
                id: String(entry.id),
                name: teamName.isEmpty ? (entry.abbrev ?? "Team \(entry.id)") : teamName,
                ownerName: owner.flatMap { $0.displayName ?? [$0.firstName, $0.lastName].compactMap { $0 }.joined(separator: " ") },
                athleteIDs: roster.map { athleteID(playerID: $0.playerId) },
                starterIDs: roster.filter { !benchSlots.contains($0.lineupSlotId ?? 20) }.map { athleteID(playerID: $0.playerId) }
            )
        }
        // SWID is the signed-in user's member ID, braces and all.
        let myTeam = swid.flatMap { swid in
            (response.teams ?? []).first { ($0.owners ?? []).contains(swid) || $0.primaryOwner == swid }
        }
        return FantasyLeague(
            id: id, provider: .espn, providerLeagueID: leagueID, name: name, season: response.seasonId ?? season,
            sport: .nfl, scoring: scoring, teams: teams, myTeamID: myTeam.map { String($0.id) },
            unsupportedRules: unsupported.sorted(), importedAt: importedAt
        )
    }
}

extension FantasyLeague {
    enum CodingKeys: String, CodingKey {
        case id, provider, providerLeagueID, name, season, sport, scoring, teams, myTeamID, unsupportedRules, importedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        provider = try c.decode(Provider.self, forKey: .provider)
        providerLeagueID = try c.decode(String.self, forKey: .providerLeagueID)
        name = try c.decode(String.self, forKey: .name)
        season = try c.decode(Int.self, forKey: .season)
        sport = try FantasySportCoding.decode(c, forKey: .sport)
        scoring = try c.decode(FantasyScoring.self, forKey: .scoring)
        teams = try c.decode([Team].self, forKey: .teams)
        myTeamID = try c.decodeIfPresent(String.self, forKey: .myTeamID)
        unsupportedRules = (try? c.decodeIfPresent([String].self, forKey: .unsupportedRules)) ?? []
        importedAt = try c.decode(Date.self, forKey: .importedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(provider, forKey: .provider)
        try c.encode(providerLeagueID, forKey: .providerLeagueID)
        try c.encode(name, forKey: .name)
        try c.encode(season, forKey: .season)
        try c.encode(sport.rawValue, forKey: .sport)
        try c.encode(scoring, forKey: .scoring)
        try c.encode(teams, forKey: .teams)
        try c.encodeIfPresent(myTeamID, forKey: .myTeamID)
        try c.encode(unsupportedRules, forKey: .unsupportedRules)
        try c.encode(importedAt, forKey: .importedAt)
    }
}
