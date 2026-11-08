//
//  PlayerBoxScore.swift
//  SportsCalModel
//
//  Per-player stat lines for one game (basketball, hockey, football, baseball), built
//  from `boxscore.players` on ESPN's per-event summary — the same fetch that feeds
//  the play-by-play. Rides on `/plays/:eventID` (opt-in with `players=1`), never on
//  `/schedules` or the live socket: a full box runs to 10–20KB.
//

import Foundation

/// Both teams' player stat tables, in ESPN's order (away first).
public struct PlayerBoxScore: Codable, Equatable, Hashable, Sendable {
    public var teams: [Team]

    public init(teams: [Team]) {
        self.teams = teams
    }

    public var home: Team? { teams.first { $0.homeAway == "home" } }
    public var away: Team? { teams.first { $0.homeAway == "away" } }

    public struct Team: Codable, Equatable, Hashable, Sendable, Identifiable {
        /// ESPN team ID.
        public var id: String
        public var abbreviation: String?
        /// "home" or "away".
        public var homeAway: String?
        /// Display order: starters then bench, forwards/defense/goalies,
        /// passing/rushing/receiving…, batting then pitching.
        public var groups: [Group]

        public init(id: String, abbreviation: String? = nil, homeAway: String? = nil, groups: [Group]) {
            self.id = id
            self.abbreviation = abbreviation
            self.homeAway = homeAway
            self.groups = groups
        }

        public func group(_ id: String) -> Group? { groups.first { $0.id == id } }
    }

    /// One stat table: a header of ESPN's column labels and a row per player.
    public struct Group: Codable, Equatable, Hashable, Sendable, Identifiable {
        /// "starters", "bench", "forwards", "goalies", "passing", "batting"…
        public var id: String
        public var title: String
        /// ESPN's column labels ("PTS", "SV%", "C/ATT").
        public var labels: [String]
        /// Spelled-out column names ("Points"), for VoiceOver. Same length as `labels`.
        public var descriptions: [String]?
        public var rows: [Row]
        /// The team line, where ESPN sends one. Same length as `labels`.
        public var totals: [String]?

        public init(id: String, title: String, labels: [String], descriptions: [String]? = nil, rows: [Row], totals: [String]? = nil) {
            self.id = id
            self.title = title
            self.labels = labels
            self.descriptions = descriptions
            self.rows = rows
            self.totals = totals
        }
    }

    public struct Row: Codable, Equatable, Hashable, Sendable, Identifiable {
        /// ESPN athlete ID.
        public var id: String
        /// "A. Dybantsa".
        public var name: String
        public var fullName: String?
        public var jersey: String?
        /// "F", "LF", "SP".
        public var position: String?
        public var headshot: String?
        /// One value per column; empty for a player who didn't play.
        public var stats: [String]
        /// Set (true) only for starters; nil otherwise, to keep the payload small.
        public var starter: Bool?
        public var didNotPlay: Bool?
        /// Why a player sat ("COACH'S DECISION", an injury).
        public var reason: String?
        /// Baseball pitching decision ("W, 2-0", "S, 31").
        public var note: String?

        public init(
            id: String, name: String, fullName: String? = nil, jersey: String? = nil,
            position: String? = nil, headshot: String? = nil, stats: [String],
            starter: Bool? = nil, didNotPlay: Bool? = nil, reason: String? = nil, note: String? = nil
        ) {
            self.id = id
            self.name = name
            self.fullName = fullName
            self.jersey = jersey
            self.position = position
            self.headshot = headshot
            self.stats = stats
            self.starter = starter
            self.didNotPlay = didNotPlay
            self.reason = reason
            self.note = note
        }

        public var isStarter: Bool { starter == true }
        public var isDNP: Bool { didNotPlay == true || stats.isEmpty }
    }
}

// MARK: - Building from the ESPN summary

public extension PlayerBoxScore {
    /// Builds the box from a summary. Nil for sports without player lines (soccer has
    /// its own match centre; golf/tennis/racing have none) or before anyone has played.
    init?(boxscore: ESPNSummaryBoxscore?, sport: SportType) {
        guard Self.supports(sport), let players = boxscore?.players, !players.isEmpty else { return nil }
        // `players[]` carries no home/away; the team-stats block alongside it does.
        var sides: [String: String] = [:]
        for team in boxscore?.teams ?? [] {
            if let id = team.team?.id, let side = team.homeAway { sides[id] = side }
        }
        let teams: [Team] = players.compactMap { entry in
            guard let id = entry.team?.id else { return nil }
            let groups = Self.groups(from: entry.statistics ?? [], sport: sport)
            guard !groups.isEmpty else { return nil }
            return Team(id: id, abbreviation: entry.team?.abbreviation, homeAway: sides[id], groups: groups)
        }
        guard !teams.isEmpty else { return nil }
        self.init(teams: teams)
    }

    static func supports(_ sport: SportType) -> Bool {
        switch sport {
        case .basketball, .hockey, .nfl, .mlb: return true
        case .soccer, .golf, .tennis, .racing: return false
        }
    }
}

extension PlayerBoxScore {
    /// Football groups worth a table, in display order. Fumbles and return lines are
    /// left out: they're a row or two each and mostly repeat the scoring summary.
    static let footballGroups = ["passing", "rushing", "receiving", "defensive", "interceptions", "kicking", "punting"]

    static func groups(from statistics: [ESPNSummaryBoxscore.PlayerGroup], sport: SportType) -> [Group] {
        var out: [Group] = []
        for raw in statistics {
            let key = raw.name ?? raw.type ?? ""
            if sport == .nfl, !footballGroups.contains(key) { continue }
            let columns = Self.columnIndices(keys: raw.keys ?? [], wanted: Self.columns(sport: sport, group: key))
            let labels = Self.pick(raw.labels ?? [], at: columns)
            guard !labels.isEmpty else { continue }
            let descriptions = raw.descriptions.map { Self.pick($0, at: columns) }
            let totals = raw.totals.flatMap { $0.isEmpty ? nil : Self.pick($0, at: columns) }
            let rows = (raw.athletes ?? []).compactMap { Self.row(from: $0, columns: columns) }
            guard !rows.isEmpty else { continue }

            if sport == .basketball {
                // One flat list from ESPN; split it the way every box score reads.
                let starters = rows.filter(\.isStarter)
                let bench = rows.filter { !$0.isStarter }
                if !starters.isEmpty {
                    out.append(Group(id: "starters", title: "Starters", labels: labels, descriptions: descriptions,
                                     rows: starters, totals: bench.isEmpty ? totals : nil))
                }
                if !bench.isEmpty {
                    out.append(Group(id: "bench", title: "Bench", labels: labels, descriptions: descriptions,
                                     rows: bench, totals: totals))
                }
                continue
            }
            out.append(Group(id: key, title: Self.title(for: key, sport: sport), labels: labels,
                             descriptions: descriptions, rows: rows, totals: totals))
        }
        return out
    }

    /// The ESPN stat keys to keep for a table, in order; nil keeps every column.
    /// ESPN's hockey and baseball tables carry year-to-date and duplicate columns
    /// (YTDG, H-AB beside H and AB) that crowd out the ones people read.
    static func columns(sport: SportType, group: String) -> [String]? {
        switch (sport, group) {
        case (.hockey, "goalies"):
            return ["shotsAgainst", "goalsAgainst", "saves", "savePct", "timeOnIce"]
        case (.hockey, _):
            return ["goals", "assists", "plusMinus", "shotsTotal", "hits", "blockedShots",
                    "penaltyMinutes", "faceoffPercent", "timeOnIce"]
        case (.mlb, "batting"):
            return ["atBats", "runs", "hits", "RBIs", "homeRuns", "walks", "strikeouts", "avg", "onBasePct", "slugAvg"]
        case (.mlb, "pitching"):
            return ["fullInnings.partInnings", "hits", "runs", "earnedRuns", "walks", "strikeouts",
                    "homeRuns", "pitches-strikes", "ERA"]
        default:
            return nil
        }
    }

    /// Positions of `wanted` within `keys`. Falls back to every column when ESPN has
    /// renamed them all, so a changed feed degrades to a wide table, not an empty one.
    static func columnIndices(keys: [String], wanted: [String]?) -> [Int] {
        let all = Array(keys.indices)
        guard let wanted else { return all }
        let picked = wanted.compactMap { keys.firstIndex(of: $0) }
        return picked.isEmpty ? all : picked
    }

    static func pick(_ values: [String], at indices: [Int]) -> [String] {
        indices.map { $0 < values.count ? values[$0] : "" }
    }

    static func row(from raw: ESPNSummaryBoxscore.PlayerLine, columns: [Int]) -> Row? {
        guard let athlete = raw.athlete, let id = athlete.id else { return nil }
        let fullName = athlete.displayName
        guard let name = athlete.shortName ?? fullName.map(Self.shortName(from:)) else { return nil }
        let stats = raw.stats ?? []
        let dnp = raw.didNotPlay == true || stats.isEmpty
        return Row(
            id: id,
            name: name,
            fullName: fullName,
            jersey: athlete.jersey,
            position: raw.position?.abbreviation ?? athlete.position?.abbreviation,
            headshot: athlete.headshot?.href,
            stats: dnp ? [] : Self.pick(stats, at: columns),
            starter: raw.starter == true ? true : nil,
            didNotPlay: dnp ? true : nil,
            reason: dnp ? raw.reason : nil,
            note: raw.notes?.first(where: { $0.type == "pitchingDecision" })?.text
        )
    }

    /// "Trevor Lawrence" → "T. Lawrence". ESPN's football box sends no short name.
    static func shortName(from full: String) -> String {
        let parts = full.split(separator: " ")
        guard parts.count > 1, let initial = parts.first?.first else { return full }
        return "\(initial). " + parts.dropFirst().joined(separator: " ")
    }

    static func title(for key: String, sport: SportType) -> String {
        switch key {
        case "forwards": return "Forwards"
        case "defenses", "defensive": return "Defense"
        case "skaters": return "Skaters"
        case "goalies": return "Goalies"
        case "passing": return "Passing"
        case "rushing": return "Rushing"
        case "receiving": return "Receiving"
        case "interceptions": return "Interceptions"
        case "kicking": return "Kicking"
        case "punting": return "Punting"
        case "batting": return "Batting"
        case "pitching": return "Pitching"
        default: return key.prefix(1).uppercased() + key.dropFirst()
        }
    }
}

// MARK: - ESPN summary `boxscore.players`

public extension ESPNSummaryBoxscore {
    struct TeamRef: Codable, Sendable {
        public var id: String?
        public var abbreviation: String?
    }

    /// One team's entry in `boxscore.players`.
    struct PlayerTeam: Codable {
        public var team: TeamRef?
        public var statistics: [PlayerGroup]?

        enum CodingKeys: String, CodingKey { case team, statistics }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            team = try? c.decodeIfPresent(TeamRef.self, forKey: .team)
            statistics = try? c.decodeIfPresent([PlayerGroup].self, forKey: .statistics)
        }
    }

    /// One stat table. Hockey and football name it (`name`), baseball types it
    /// (`type`), basketball sends a single unnamed one.
    struct PlayerGroup: Codable {
        public var name: String?
        public var type: String?
        public var keys: [String]?
        public var labels: [String]?
        public var descriptions: [String]?
        public var totals: [String]?
        public var athletes: [PlayerLine]?

        enum CodingKeys: String, CodingKey { case name, type, keys, labels, descriptions, totals, athletes }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            type = try? c.decodeIfPresent(String.self, forKey: .type)
            keys = try? c.decodeIfPresent([String].self, forKey: .keys)
            labels = try? c.decodeIfPresent([String].self, forKey: .labels)
            descriptions = try? c.decodeIfPresent([String].self, forKey: .descriptions)
            totals = try? c.decodeIfPresent([String].self, forKey: .totals)
            // Per athlete, so one odd row can't cost the table.
            athletes = (try? c.decodeIfPresent([LossyLine].self, forKey: .athletes))?.compactMap(\.line)
        }

        private struct LossyLine: Decodable {
            let line: PlayerLine?
            init(from decoder: Decoder) throws { line = try? PlayerLine(from: decoder) }
        }
    }

    struct PlayerLine: Codable {
        public var athlete: Athlete?
        public var stats: [String]?
        public var starter: Bool?
        public var didNotPlay: Bool?
        public var reason: String?
        /// Baseball's lineup position (the athlete's own is their primary one).
        public var position: Position?
        public var notes: [Note]?

        public struct Athlete: Codable {
            public var id: String?
            public var displayName: String?
            public var shortName: String?
            public var jersey: String?
            public var headshot: Headshot?
            public var position: Position?
        }

        public struct Headshot: Codable { public var href: String? }
        public struct Position: Codable { public var abbreviation: String? }
        public struct Note: Codable {
            public var type: String?
            public var text: String?
        }

        enum CodingKeys: String, CodingKey { case athlete, stats, starter, didNotPlay, reason, position, notes }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            athlete = try c.decodeIfPresent(Athlete.self, forKey: .athlete)
            stats = try? c.decodeIfPresent([String].self, forKey: .stats)
            starter = try? c.decodeIfPresent(Bool.self, forKey: .starter)
            didNotPlay = try? c.decodeIfPresent(Bool.self, forKey: .didNotPlay)
            reason = try? c.decodeIfPresent(String.self, forKey: .reason)
            position = try? c.decodeIfPresent(Position.self, forKey: .position)
            notes = try? c.decodeIfPresent([Note].self, forKey: .notes)
        }
    }
}
