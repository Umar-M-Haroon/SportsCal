// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let competitor = try? newJSONDecoder().decode(Competitor.self, from: jsonData)

import Foundation

// MARK: - Competitor
public struct Competitor: Codable {
    public var id, uid: String
    public var type: String
    /// Finishing/grid order. ESPN omits this for not-yet-contested events (e.g. a future
    /// F1 race), so it must be optional or the whole scoreboard decode fails.
    public var order: Int?
    public var homeAway: String?
    public var team: CompetitorTeam?
    public var athlete: Athlete?
    public var score: String?
    public var linescores: [Linescore]?
    public var statistics: [Statistic]?
    public var leaders: [CompetitorLeader]?
    public var records: [Record]?
    public var curatedRank: CuratedRank?
    /// Tennis doubles: the pair's names live here ("Hugo Nys / Edouard
    /// Roger-Vasselin"), NOT on `team`/`athlete` — without it doubles decode as "TBD".
    public var roster: Roster?

    public struct CuratedRank: Codable {
        public var current: Int?
    }

    public struct Roster: Codable {
        public var displayName: String?
        public var shortDisplayName: String?
    }

    public init(id: String, uid: String, type: String, order: Int? = nil, homeAway: String? = nil, team: CompetitorTeam? = nil, score: String? = nil, linescores: [Linescore]? = nil, statistics: [Statistic]? = nil, leaders: [CompetitorLeader]? = nil, records: [Record]? = nil, curatedRank: CuratedRank? = nil) {
        self.id = id
        self.uid = uid
        self.type = type
        self.order = order
        self.homeAway = homeAway
        self.team = team
        self.score = score
        self.linescores = linescores
        self.statistics = statistics
        self.leaders = leaders
        self.records = records
        self.curatedRank = curatedRank
    }
}
