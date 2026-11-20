//
//  CricketScorecard.swift
//  SportsCalModel
//
//  A cricket match's full card — every innings' batters and bowlers — built from ESPN's
//  match summary (`/sports/cricket/{league}/summary?event={id}`). The server builds it and
//  serves the compact form on `/cricket/match/:id`; the app shows it in the match detail.
//
//  ESPN files each player's figures under `rosters[].roster[].linescores[]`, one entry per
//  innings (`period`), as loose name/value stat lists. Batting and bowling for the same
//  innings sit on opposite rosters.
//

import Foundation

public struct CricketScorecard: Codable, Equatable, Sendable {
    public struct Batter: Codable, Equatable, Hashable, Sendable {
        public var name: String
        public var playerID: String?
        /// "c Pant b Bumrah", "not out". Nil when ESPN gave no wording.
        public var dismissal: String?
        public var runs: Int
        public var balls: Int
        public var fours: Int
        public var sixes: Int
        public var strikeRate: Double?
        public var isOut: Bool
        /// At the crease now.
        public var isBatting: Bool?

        public init(name: String, playerID: String? = nil, dismissal: String? = nil, runs: Int, balls: Int,
                    fours: Int = 0, sixes: Int = 0, strikeRate: Double? = nil, isOut: Bool, isBatting: Bool? = nil) {
            self.name = name
            self.playerID = playerID
            self.dismissal = dismissal
            self.runs = runs
            self.balls = balls
            self.fours = fours
            self.sixes = sixes
            self.strikeRate = strikeRate
            self.isOut = isOut
            self.isBatting = isBatting
        }
    }

    public struct Bowler: Codable, Equatable, Hashable, Sendable {
        public var name: String
        public var playerID: String?
        public var overs: Double
        public var maidens: Int
        public var runs: Int
        public var wickets: Int
        public var economy: Double?

        public init(name: String, playerID: String? = nil, overs: Double, maidens: Int = 0, runs: Int,
                    wickets: Int, economy: Double? = nil) {
            self.name = name
            self.playerID = playerID
            self.overs = overs
            self.maidens = maidens
            self.runs = runs
            self.wickets = wickets
            self.economy = economy
        }

        /// "4-92".
        public var figures: String { "\(wickets)-\(runs)" }
    }

    public struct Innings: Codable, Equatable, Sendable, Identifiable {
        public var number: Int
        public var battingSide: GameSituation.Side
        public var battingTeam: String
        /// "368", "159/1".
        public var total: String?
        public var overs: Double?
        /// "(nb 6)".
        public var extras: String?
        public var batters: [Batter]
        public var bowlers: [Bowler]
        /// In batting order, for an innings still going.
        public var yetToBat: [String]

        public var id: Int { number }

        public init(number: Int, battingSide: GameSituation.Side, battingTeam: String, total: String? = nil,
                    overs: Double? = nil, extras: String? = nil, batters: [Batter], bowlers: [Bowler], yetToBat: [String] = []) {
            self.number = number
            self.battingSide = battingSide
            self.battingTeam = battingTeam
            self.total = total
            self.overs = overs
            self.extras = extras
            self.batters = batters
            self.bowlers = bowlers
            self.yetToBat = yetToBat
        }
    }

    public var eventID: String
    public var innings: [Innings]

    public init(eventID: String, innings: [Innings]) {
        self.eventID = eventID
        self.innings = innings
    }
}

// MARK: - From ESPN

public struct ESPNCricketSummary: Decodable {
    struct Roster: Decodable {
        var homeAway: String?
        var team: Team?
        var roster: [Player]?
    }

    struct Team: Decodable {
        var displayName: String?
    }

    struct Player: Decodable {
        var starter: Bool?
        var athlete: Athlete?
        var linescores: [Period]?
    }

    struct Athlete: Decodable {
        var id: String?
        var displayName: String?
    }

    struct Period: Decodable {
        var period: Int?
        var linescores: [Entry]?
    }

    struct Entry: Decodable {
        var statistics: Statistics?
    }

    struct Statistics: Decodable {
        var categories: [Category]?
        /// Dismissal and at-the-crease flag. Present for some batters only.
        var batting: Batting?
    }

    struct Category: Decodable {
        var stats: [Stat]?
    }

    struct Stat: Decodable {
        var name: String?
        var value: ESPNFlexibleNumber?
        var displayValue: String?
    }

    struct Batting: Decodable {
        var active: Bool?
        var outDetails: OutDetails?
    }

    struct OutDetails: Decodable {
        var shortText: String?
    }

    struct Header: Decodable {
        var id: String?
        var competitions: [ESPNCricketBoard.Match]?
    }

    /// The current innings' card, which carries ESPN's dismissal wording.
    struct MatchCard: Decodable {
        var headline: String?
        var inningsNumber: String?
        var extras: String?
        var playerDetails: [CardPlayer]?
    }

    struct CardPlayer: Decodable {
        var playerID: String?
        var dismissal: String?
    }

    var rosters: [Roster]?
    var header: Header?
    var matchcards: [MatchCard]?

    /// The full card, or nil when ESPN had no player figures (before the toss).
    public func scorecard(eventID: String) -> CricketScorecard? {
        struct Line {
            var player: Player
            var stats: [String: Double]
            var batting: Batting?
        }
        var batting: [Int: [GameSituation.Side: [(position: Int, line: Line)]]] = [:]
        var bowling: [Int: [(position: Int, line: Line)]] = [:]
        var squads: [GameSituation.Side: [String]] = [:]
        var teamNames: [GameSituation.Side: String] = [:]

        for roster in rosters ?? [] {
            guard let side: GameSituation.Side = roster.homeAway == "home" ? .home : (roster.homeAway == "away" ? .away : nil) else { continue }
            teamNames[side] = roster.team?.displayName
            for player in roster.roster ?? [] {
                if player.starter != false, let name = player.athlete?.displayName { squads[side, default: []].append(name) }
                for period in player.linescores ?? [] {
                    guard let number = period.period else { continue }
                    for entry in period.linescores ?? [] {
                        var stats: [String: Double] = [:]
                        for category in entry.statistics?.categories ?? [] {
                            for stat in category.stats ?? [] {
                                if let name = stat.name, let value = stat.value?.value { stats[name] = value }
                            }
                        }
                        let line = Line(player: player, stats: stats, batting: entry.statistics?.batting)
                        if stats["batted"] == 1 {
                            let position = Int(stats["battingPosition"] ?? 99)
                            batting[number, default: [:]][side, default: []].append((position, line))
                        }
                        if stats["inningsBowled"] == 1 || (stats["balls"] ?? 0) > 0 {
                            let position = Int(stats["bowlingPosition"] ?? 99)
                            bowling[number, default: []].append((position, line))
                        }
                    }
                }
            }
        }
        guard !batting.isEmpty else { return nil }

        let competitors = header?.competitions?.first?.competitors ?? []
        func totals(_ side: GameSituation.Side, _ number: Int) -> ESPNCricketBoard.Innings? {
            competitors.first { $0.homeAway == (side == .home ? "home" : "away") }?
                .linescores?.first { $0.period == number && $0.isBatting == true }
        }
        let cardDismissals = Dictionary(
            (matchcards ?? []).flatMap { $0.playerDetails ?? [] }
                .compactMap { card in card.playerID.flatMap { id in card.dismissal.map { (id, $0) } } },
            uniquingKeysWith: { first, _ in first }
        )

        let innings: [CricketScorecard.Innings] = batting.keys.sorted().compactMap { number in
            guard let (side, lines) = batting[number]?.first else { return nil }
            let batters = lines.sorted { $0.position < $1.position }.map { _, line -> CricketScorecard.Batter in
                let stats = line.stats
                let out = (stats["outs"] ?? 0) > 0
                let id = line.player.athlete?.id
                let wording = line.batting?.outDetails?.shortText.map(Self.plainText)
                    ?? id.flatMap { cardDismissals[$0] }.flatMap { $0.isEmpty ? nil : $0 }
                return CricketScorecard.Batter(
                    name: line.player.athlete?.displayName ?? "",
                    playerID: id,
                    dismissal: wording ?? (out ? nil : "not out"),
                    runs: Int(stats["runs"] ?? 0),
                    balls: Int(stats["ballsFaced"] ?? 0),
                    fours: Int(stats["fours"] ?? 0),
                    sixes: Int(stats["sixes"] ?? 0),
                    strikeRate: stats["strikeRate"],
                    isOut: out,
                    isBatting: line.batting?.active == true ? true : nil
                )
            }
            let bowlers = (bowling[number] ?? []).sorted { $0.position < $1.position }.map { _, line in
                CricketScorecard.Bowler(
                    name: line.player.athlete?.displayName ?? "",
                    playerID: line.player.athlete?.id,
                    overs: line.stats["overs"] ?? 0,
                    maidens: Int(line.stats["maidens"] ?? 0),
                    runs: Int(line.stats["conceded"] ?? 0),
                    wickets: Int(line.stats["wickets"] ?? 0),
                    economy: line.stats["economyRate"]
                )
            }
            let total = totals(side, number)
            let batted = Set(batters.map(\.name))
            let card = (matchcards ?? []).first { $0.headline == "Batting" && $0.inningsNumber == "\(number)" }
            let isLastInnings = number == batting.keys.max()
            return CricketScorecard.Innings(
                number: number,
                battingSide: side,
                battingTeam: teamNames[side] ?? "",
                total: total.map { CricketInnings(side: side, number: number, runs: $0.runs ?? 0, wickets: $0.wickets ?? 0).scoreText },
                overs: total?.overs,
                extras: card?.extras,
                batters: batters,
                bowlers: bowlers,
                yetToBat: isLastInnings && batters.count < 11 ? (squads[side] ?? []).filter { !batted.contains($0) } : []
            )
        }
        return CricketScorecard(eventID: eventID, innings: innings)
    }

    /// ESPN's wording is HTML: "c &dagger;Pant b Kamboj" (the dagger marks the keeper).
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, character) in [("&dagger;", "†"), ("&amp;", "&"), ("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
