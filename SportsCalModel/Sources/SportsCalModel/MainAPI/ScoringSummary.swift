//
//  ScoringSummary.swift
//  SportsCalModel
//
//  The scoring plays of one game, oldest first: football scores by quarter, hockey
//  goals (scorer, assists, PP/SH/EN) and penalties by period, baseball runs by
//  inning. Built from ESPN's per-event summary beside the play-by-play and shipped
//  with it on `/plays/:eventID` (opt-in with `players=1`).
//
//  Soccer has its own match-centre timeline; basketball scores too often for a
//  summary to say anything the play-by-play doesn't.
//

import Foundation

public struct ScoringSummary: Codable, Equatable, Hashable, Sendable {
    public var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public struct Entry: Codable, Equatable, Hashable, Sendable, Identifiable {
        /// ESPN play ID.
        public var id: String
        public var period: Int
        /// Baseball's half-inning: "Top" or "Bottom".
        public var half: String?
        public var clock: String?
        /// "home" or "away": the side that scored, or the side penalized.
        public var side: String?
        public var teamAbbreviation: String?
        /// Football and baseball: ESPN's play description. Hockey goals: the shot
        /// ("Wrist Shot"). Penalties: the infraction ("Tripping").
        public var text: String
        /// Hockey: the goal scorer, or the penalized player.
        public var player: String?
        /// Hockey: the assisting players, primary first.
        public var assists: [String]?
        /// Hockey: "PP", "SH", "EN", "SO". Football: "TD", "FG", "SF", "2PT".
        public var tags: [String]?
        public var awayScore: Int?
        public var homeScore: Int?
        /// Set only for hockey penalties.
        public var penaltyMinutes: Int?

        public init(
            id: String, period: Int, half: String? = nil, clock: String? = nil, side: String? = nil,
            teamAbbreviation: String? = nil, text: String, player: String? = nil, assists: [String]? = nil,
            tags: [String]? = nil, awayScore: Int? = nil, homeScore: Int? = nil, penaltyMinutes: Int? = nil
        ) {
            self.id = id
            self.period = period
            self.half = half
            self.clock = clock
            self.side = side
            self.teamAbbreviation = teamAbbreviation
            self.text = text
            self.player = player
            self.assists = assists
            self.tags = tags
            self.awayScore = awayScore
            self.homeScore = homeScore
            self.penaltyMinutes = penaltyMinutes
        }

        public var isPenalty: Bool { penaltyMinutes != nil }
        public var isShootout: Bool { tags?.contains("SO") == true }
    }

    /// Entries grouped by period, in period order. Shootout attempts go last under
    /// their own key (-1) whatever period ESPN numbered them.
    public var byPeriod: [(period: Int, entries: [Entry])] {
        var order: [Int] = []
        var groups: [Int: [Entry]] = [:]
        for entry in entries {
            let key = entry.isShootout ? -1 : entry.period
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }
        let sorted = order.sorted { lhs, rhs in
            if lhs == -1 { return false }
            if rhs == -1 { return true }
            return lhs < rhs
        }
        return sorted.map { (period: $0, entries: groups[$0] ?? []) }
    }
}

// MARK: - Building from the ESPN summary

public extension ScoringSummary {
    /// Nil for sports without a summary card and for games with nothing to list.
    init?(summary: ESPNSummaryResponse, sport: SportType) {
        var sides: [String: String] = [:]
        var abbreviations: [String: String] = [:]
        for team in summary.boxscore?.teams ?? [] {
            guard let id = team.team?.id else { continue }
            if let side = team.homeAway { sides[id] = side }
            if let abbreviation = team.team?.abbreviation { abbreviations[id] = abbreviation }
        }
        let entries: [Entry]
        switch sport {
        case .nfl:
            entries = (summary.scoringPlays ?? []).compactMap { Self.footballEntry($0, sides: sides) }
        case .hockey:
            entries = (summary.detailPlays ?? []).compactMap { Self.hockeyEntry($0, sides: sides, abbreviations: abbreviations) }
        case .mlb:
            entries = (summary.detailPlays ?? []).compactMap { Self.baseballEntry($0, sides: sides, abbreviations: abbreviations) }
        case .basketball, .soccer, .golf, .tennis, .racing:
            return nil
        }
        guard !entries.isEmpty else { return nil }
        self.init(entries: entries)
    }
}

extension ScoringSummary {
    static func footballEntry(_ play: ESPNSummaryResponse.ScoringPlay, sides: [String: String]) -> Entry? {
        guard let id = play.id, let text = play.text, let period = play.period?.number else { return nil }
        let teamID = play.team?.id
        let tag = play.type?.abbreviation ?? play.scoringType?.abbreviation
        return Entry(
            id: id, period: period, clock: play.clock?.displayValue,
            side: teamID.flatMap { sides[$0] }, teamAbbreviation: play.team?.abbreviation,
            text: text, tags: tag.map { [$0] },
            awayScore: play.awayScore, homeScore: play.homeScore
        )
    }

    static func hockeyEntry(_ play: ESPNSummaryResponse.DetailPlay, sides: [String: String], abbreviations: [String: String]) -> Entry? {
        guard let id = play.id, let period = play.period?.number else { return nil }
        let teamID = play.team?.id
        let side = teamID.flatMap { sides[$0] }
        let abbreviation = teamID.flatMap { abbreviations[$0] }

        // Penalties carry their minutes on the play type.
        if let minutesText = play.type?.penaltyMinutes, let minutes = Int(minutesText) {
            let infraction = play.type?.text ?? play.text ?? "Penalty"
            let player = play.participants?.first?.athlete?.shortName
            return Entry(
                id: id, period: period, clock: play.clock?.displayValue, side: side,
                teamAbbreviation: abbreviation, text: infraction, player: player, penaltyMinutes: minutes
            )
        }
        guard play.scoringPlay == true else { return nil }
        let participants = play.participants ?? []
        let scorer = participants.first { $0.type == "scorer" }?.athlete?.shortName
            ?? participants.first?.athlete?.shortName
        let assists = participants.filter { $0.type == "assister" }.compactMap { $0.athlete?.shortName }
        return Entry(
            id: id, period: period, clock: play.clock?.displayValue, side: side,
            teamAbbreviation: abbreviation, text: Self.shotKind(from: play.text) ?? "Goal",
            player: scorer, assists: assists.isEmpty ? nil : assists,
            tags: Self.hockeyTags(play), awayScore: play.awayScore, homeScore: play.homeScore
        )
    }

    /// PP/SH from the strength; EN and SO from the shot (ESPN files an empty-net goal
    /// under both). A playoff 2OT is period 5 too, so the shootout is read off the
    /// shot, never the period number.
    static func hockeyTags(_ play: ESPNSummaryResponse.DetailPlay) -> [String]? {
        var tags: [String] = []
        switch play.strength?.abbreviation {
        case "power-play": tags.append("PP")
        case "short-handed": tags.append("SH")
        default: break
        }
        if play.strength?.abbreviation == "empty-net" || play.shotInfo?.abbreviation == "empty-net" || play.shotInfo?.id == "903" {
            tags.append("EN")
        }
        if play.shotInfo?.id == "905" || play.shotInfo?.text == "Shootout" {
            tags.append("SO")
        }
        return tags.isEmpty ? nil : tags
    }

    /// "Jack Quinn Goal (9) Backhand, assists: …" → "Backhand".
    static func shotKind(from text: String?) -> String? {
        guard let text, let goal = text.range(of: " Goal") else { return nil }
        var rest = text[goal.upperBound...]
        if let comma = rest.firstIndex(of: ",") { rest = rest[..<comma] }
        // Drop the season tally: "(9) Backhand".
        if let close = rest.firstIndex(of: ")"), rest.trimmingCharacters(in: .whitespaces).hasPrefix("(") {
            rest = rest[rest.index(after: close)...]
        }
        let kind = rest.trimmingCharacters(in: .whitespaces)
        return kind.isEmpty ? nil : kind
    }

    static func baseballEntry(_ play: ESPNSummaryResponse.DetailPlay, sides: [String: String], abbreviations: [String: String]) -> Entry? {
        guard play.scoringPlay == true, let id = play.id, let text = play.text, !text.isEmpty,
              let period = play.period?.number else { return nil }
        let teamID = play.team?.id
        // The batting side is the scoring side: the visitors bat in the top half.
        var side = teamID.flatMap { sides[$0] }
        if side == nil, let half = play.period?.type {
            side = half == "Top" ? "away" : "home"
        }
        return Entry(
            id: id, period: period, half: play.period?.type, side: side,
            teamAbbreviation: teamID.flatMap { abbreviations[$0] },
            text: text, awayScore: play.awayScore, homeScore: play.homeScore
        )
    }
}

// MARK: - ESPN summary fields for the summary

public extension ESPNSummaryResponse {
    /// Football's top-level `scoringPlays`: one per score, with ESPN's tidy
    /// "Bhayshul Tuten 1 Yd Rush (Cam Little Kick)" text.
    struct ScoringPlay: Codable {
        public var id: String?
        public var text: String?
        public var awayScore: Int?
        public var homeScore: Int?
        public var period: Period?
        public var clock: Clock?
        public var team: ESPNSummaryBoxscore.TeamRef?
        public var type: Kind?
        public var scoringType: Kind?

        public struct Period: Codable {
            public var number: Int?
            /// Baseball: "Top" / "Bottom".
            public var type: String?
        }
        public struct Clock: Codable { public var displayValue: String? }
        public struct Kind: Codable {
            public var id: String?
            public var text: String?
            public var abbreviation: String?
            /// Hockey penalties: "2".
            public var penaltyMinutes: String?
        }
    }

    /// The fields of `plays[]` the summary needs beyond `Play`: who was involved, the
    /// strength and shot type (hockey), the scoring team. Decoded beside `Play`
    /// rather than added to it, since `Play` is archived and shipped for every play.
    struct DetailPlay: Codable {
        public var id: String?
        public var text: String?
        public var scoringPlay: Bool?
        public var awayScore: Int?
        public var homeScore: Int?
        public var period: ScoringPlay.Period?
        public var clock: ScoringPlay.Clock?
        public var team: ESPNSummaryBoxscore.TeamRef?
        public var type: ScoringPlay.Kind?
        public var participants: [Participant]?
        public var strength: ScoringPlay.Kind?
        public var shotInfo: ScoringPlay.Kind?

        public struct Participant: Codable {
            public var athlete: Athlete?
            /// Hockey goals: "scorer" / "assister".
            public var type: String?
            public struct Athlete: Codable {
                public var shortName: String?
            }
        }
    }
}
