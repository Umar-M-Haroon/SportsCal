//
//  Cricket.swift
//  SportsCalModel
//
//  Cricket rides the team-sport path: two sides, badges, a score per side. What doesn't
//  fit a team sport's `Int` score lives in `CricketMatchExtras` on
//  `Game.scoreboardExtras.cricket`: the innings, the format, the session ("Day 2") and
//  ESPN's one-line state ("India trail by 209 runs").
//
//  `Game.intHomeScore` / `intAwayScore` carry ESPN's own score text ("137 & 144/2 (40 ov)",
//  "392/9d") so anything that just prints the score reads right without knowing cricket.
//  Never compare those to find a winner: DLS can hand a match to the side with fewer
//  runs. `homeWinner` / `awayWinner` come from ESPN.
//

import Foundation

// MARK: - Format

public enum CricketFormat: String, Codable, Sendable, CaseIterable {
    case test, odi, t20, hundred, t10, firstClass, listA, other

    public init(from decoder: Decoder) throws {
        // A format added by a newer server reads as `.other`, not a failed game.
        self = (try? CricketFormat(rawValue: decoder.singleValueContainer().decode(String.self))) ?? .other
    }

    /// From ESPN's `class` block. International matches are named by `internationalClassId`
    /// (1 Test, 2 ODI, 3 T20I); everything else by `eventType` ("Test" = first-class,
    /// "ODI" = List A, "T20").
    public init(internationalClassID: Int?, eventType: String?, leagueName: String? = nil) {
        if leagueName?.localizedCaseInsensitiveContains("hundred") == true {
            self = .hundred
            return
        }
        switch internationalClassID {
        case 1: self = .test; return
        case 2: self = .odi; return
        case 3: self = .t20; return
        default: break
        }
        let international = (internationalClassID ?? 0) != 0
        switch eventType?.uppercased() {
        case "TEST": self = international ? .test : .firstClass
        case "ODI": self = international ? .odi : .listA
        case "T20": self = .t20
        case "T10": self = .t10
        default: self = .other
        }
    }

    /// "Test", "ODI", "T20", …
    public var displayName: String {
        switch self {
        case .test: "Test"
        case .odi: "ODI"
        case .t20: "T20"
        case .hundred: "The Hundred"
        case .t10: "T10"
        case .firstClass: "First-class"
        case .listA: "One-day"
        case .other: "Cricket"
        }
    }

    /// Played over more than one day (Tests, first-class).
    public var isMultiDay: Bool {
        self == .test || self == .firstClass
    }
}

// MARK: - Innings

public struct CricketInnings: Codable, Equatable, Hashable, Sendable {
    public var side: GameSituation.Side
    /// The match's innings number, 1-based across both sides (a Test has up to four).
    public var number: Int
    public var runs: Int
    public var wickets: Int
    /// Overs as cricket writes them: 40.3 is 40 overs and 3 balls.
    public var overs: Double?
    public var declared: Bool
    /// Batting right now.
    public var isCurrent: Bool

    public init(side: GameSituation.Side, number: Int, runs: Int, wickets: Int, overs: Double? = nil,
                declared: Bool = false, isCurrent: Bool = false) {
        self.side = side
        self.number = number
        self.runs = runs
        self.wickets = wickets
        self.overs = overs
        self.declared = declared
        self.isCurrent = isCurrent
    }

    public var isAllOut: Bool { wickets >= 10 }

    /// "144/2", "137" (all out), "392/9d".
    public var scoreText: String {
        if isAllOut { return "\(runs)" }
        return "\(runs)/\(wickets)\(declared ? "d" : "")"
    }

    /// "40.3 ov". Nil when ESPN sent no overs.
    public var oversText: String? {
        guard let overs else { return nil }
        let whole = overs.rounded(.towardZero)
        let text = overs == whole ? String(Int(whole)) : String(format: "%.1f", overs)
        return "\(text) ov"
    }

    /// Legal balls bowled, from cricket's overs notation.
    public var balls: Int? {
        guard let overs else { return nil }
        let whole = Int(overs.rounded(.towardZero))
        let part = Int(((overs - Double(whole)) * 10).rounded())
        return whole * 6 + part
    }

    /// Runs per over.
    public var runRate: Double? {
        guard let balls, balls > 0 else { return nil }
        return Double(runs) / (Double(balls) / 6)
    }
}

// MARK: - Match payload

public struct CricketMatchExtras: Codable, Equatable, Hashable, Sendable {
    public var format: CricketFormat
    /// Every innings so far, in match order.
    public var innings: [CricketInnings]
    /// ESPN's state line: "India trail by 209 runs", "Bulls won by 7 wkts (4b rem)",
    /// "Starts at 19:15 local time".
    public var summary: String?
    /// "Day 2". Multi-day formats only.
    public var session: String?
    /// ESPN's status description: "Stumps", "Lunch", "Innings break", "Rain", "Live".
    public var statusDetail: String?
    /// Runs the side batting needs, in a chase.
    public var target: Int?
    /// Overs per side in a limited-overs match after any reduction (rain).
    public var scheduledOvers: Int?
    /// "1st T20I", "Final", "Qualifier 2".
    public var matchLabel: String?
    /// The tour or event ("England tour of Australia 2026/27", "ICC Men's T20 World Cup").
    public var seriesName: String?
    /// Abandoned without a ball, or called off.
    public var isAbandoned: Bool?
    public var isDraw: Bool?

    public init(format: CricketFormat, innings: [CricketInnings] = [], summary: String? = nil, session: String? = nil,
                statusDetail: String? = nil, target: Int? = nil, scheduledOvers: Int? = nil, matchLabel: String? = nil,
                seriesName: String? = nil, isAbandoned: Bool? = nil, isDraw: Bool? = nil) {
        self.format = format
        self.innings = innings
        self.summary = summary
        self.session = session
        self.statusDetail = statusDetail
        self.target = target
        self.scheduledOvers = scheduledOvers
        self.matchLabel = matchLabel
        self.seriesName = seriesName
        self.isAbandoned = isAbandoned
        self.isDraw = isDraw
    }

    public func innings(for side: GameSituation.Side) -> [CricketInnings] {
        innings.filter { $0.side == side }
    }

    /// The innings in progress.
    public var currentInnings: CricketInnings? {
        innings.last(where: \.isCurrent)
    }

    /// Who's batting, while live.
    public var battingSide: GameSituation.Side? {
        currentInnings?.side
    }

    /// Runs the batting side still needs, in a chase.
    public var runsRequired: Int? {
        guard let target, let current = currentInnings else { return nil }
        return Swift.max(target - current.runs, 0)
    }

    /// Runs per over needed to win, in a limited-overs chase.
    public var requiredRunRate: Double? {
        guard let required = runsRequired, let overs = scheduledOvers,
              let balls = currentInnings?.balls else { return nil }
        let remaining = overs * 6 - balls
        guard remaining > 0 else { return nil }
        return Double(required) / (Double(remaining) / 6)
    }

    /// One side's innings joined the way a scorecard header writes them: "137 & 144/2".
    public func scoreText(for side: GameSituation.Side) -> String? {
        let mine = innings(for: side)
        guard !mine.isEmpty else { return nil }
        return mine.map(\.scoreText).joined(separator: " & ")
    }
}

// MARK: - Competitions

/// Which `Leagues` case an ESPN cricket match belongs to.
///
/// ESPN gives franchise leagues a stable league id but files every international tour
/// under a fresh one ("England tour of Australia 2026/27" = 24273), so internationals are
/// routed by the match's `internationalClassId` instead and grouped by format.
public enum CricketCompetition {
    /// ESPN reuses numeric team ids across sports, so cricket's are namespaced.
    public static let teamIDPrefix = "cricket-"

    /// ESPN league id → league, for competitions with a stable id.
    public static let espnLeagues: [Int: Leagues] = [
        8048: .ipl,
        8044: .bigBash,
        8679: .psl,
        21275: .sa20,
        8623: .cpl,
        20921: .ilt20,
        21284: .wbbl,
        8043: .sheffieldShield,
        8052: .countyChampionship,   // Division One
        8204: .countyChampionship,   // Division Two
    ]

    /// The league's logo id on ESPN's CDN (County Championship: Division One's).
    public static func espnLeagueID(for league: Leagues) -> Int? {
        espnLeagues.filter { $0.value == league }.keys.min()
    }

    /// The league for one ESPN match, or nil for a competition we don't carry (domestic
    /// one-dayers, A tours, associate qualifiers, …).
    ///
    /// - Parameters:
    ///   - espnLeagueID: ESPN's league id for the match's competition.
    ///   - leagueName: ESPN's competition name, to catch leagues whose id moves per season.
    ///   - internationalClassID: `competitions[0].class.internationalClassId`.
    ///   - teamNames: both sides, to tell women's matches apart (ESPN names them
    ///     "Sri Lanka Women").
    public static func league(espnLeagueID: Int?, leagueName: String?, internationalClassID: Int?,
                              teamNames: [String]) -> Leagues? {
        if let espnLeagueID, let league = espnLeagues[espnLeagueID] { return league }
        let name = leagueName?.lowercased() ?? ""
        let women = teamNames.contains { $0.hasSuffix(" Women") } || name.contains("women")
        if let league = leagueByName(name, women: women) { return league }
        // ESPN's international classes: 1 Test, 2 ODI, 3 T20I (men); 8 Test, 9 ODI, 10 T20I
        // (women); 14/15 Under-19s. Associates play under the same classes ("Falkland
        // Islands v Costa Rica" is a T20I), so a match needs a full member on one side or
        // a place at an ICC main event.
        let worthCarrying = involvesFullMember(teamNames) || isICCMainEvent(name)
        switch internationalClassID {
        case 1 where worthCarrying: return women ? .womensCricketInternationals : .cricketTests
        case 2 where worthCarrying: return women ? .womensCricketInternationals : .cricketODIs
        case 3 where worthCarrying: return women ? .womensCricketInternationals : .cricketT20Is
        case 8, 9, 10: return worthCarrying ? .womensCricketInternationals : nil
        default: return nil
        }
    }

    /// World Cups, the Champions Trophy and the World Test Championship final, but not
    /// their qualifiers or the associate leagues that feed them.
    static func isICCMainEvent(_ name: String) -> Bool {
        let main = ["world cup", "champions trophy", "world test championship"].contains { name.contains($0) }
        let feeder = ["qualifier", "league 2", "challenge league", "sub regional", "regional final", "under-19", "u19"]
            .contains { name.contains($0) }
        return main && !feeder
    }

    /// Leagues whose ESPN id changes every season ("SA20, 2026/27"), matched by name.
    static func leagueByName(_ name: String, women: Bool) -> Leagues? {
        guard !name.isEmpty, !name.contains(" tour of ") else { return nil }
        if name.contains("hundred") { return women ? .theHundredWomen : .theHundred }
        if women { return name.contains("big bash") ? .wbbl : nil }
        if name.contains("indian premier league") { return .ipl }
        if name.contains("big bash") { return .bigBash }
        if name.contains("pakistan super league") { return .psl }
        if name.hasPrefix("sa20") { return .sa20 }
        if name.contains("caribbean premier league") { return .cpl }
        if name.contains("major league cricket") { return .mlc }
        if name.contains("international league t20") || name.hasPrefix("ilt20") { return .ilt20 }
        if name.contains("sheffield shield") { return .sheffieldShield }
        if name.contains("county championship") { return .countyChampionship }
        return nil
    }

    /// The twelve ICC full members, by ESPN's team name (women's sides carry a " Women"
    /// suffix, stripped here).
    static let fullMembers: Set<String> = [
        "Afghanistan", "Australia", "Bangladesh", "England", "India", "Ireland",
        "New Zealand", "Pakistan", "South Africa", "Sri Lanka", "West Indies", "Zimbabwe",
    ]

    static func involvesFullMember(_ teamNames: [String]) -> Bool {
        teamNames.contains { name in
            let country = name.hasSuffix(" Women") ? String(name.dropLast(" Women".count)) : name
            return fullMembers.contains(country)
        }
    }
}

// MARK: - Game

public extension Game {
    var isCricket: Bool { sportType == .cricket }

    /// The cricket payload, on cricket games the server has built one for.
    var cricket: CricketMatchExtras? { scoreboardExtras?.cricket }
}

// MARK: - Presentation

public extension Game {
    /// One side's score as a scorecard header writes it ("137 & 144/2"), falling back to
    /// ESPN's own text. Nil before the side has batted.
    func cricketScore(for side: GameSituation.Side) -> String? {
        if let text = cricket?.scoreText(for: side) { return text }
        let raw = side == .home ? intHomeScore : intAwayScore
        return raw?.isEmpty == false ? raw : nil
    }

    /// "40.3 ov" for the side batting right now.
    func cricketOvers(for side: GameSituation.Side) -> String? {
        guard let current = cricket?.currentInnings, current.side == side else { return nil }
        return current.oversText
    }

    /// The winner, as ESPN called it. Never worked out from the runs (DLS).
    var cricketWinner: GameSituation.Side? {
        if scoreboardExtras?.homeWinner == true { return .home }
        if scoreboardExtras?.awayWinner == true { return .away }
        return nil
    }

    /// "Day 2 · Stumps", "Innings break", "Live", "Final", "Drawn", "Abandoned". Nil before
    /// the start (show the time instead).
    var cricketStatusText: String? {
        switch strStatus {
        case "in":
            let detail = cricket?.statusDetail.flatMap { $0 == "Live" ? nil : $0 }
            let parts = [cricket?.session, detail].compactMap { $0 }
            return parts.isEmpty ? "Live" : parts.joined(separator: " · ")
        case "post":
            if cricket?.isAbandoned == true { return cricket?.statusDetail ?? "Abandoned" }
            if cricket?.isDraw == true { return "Drawn" }
            return "Final"
        default:
            return nil
        }
    }

    /// ESPN's state line once the match has started: "India trail by 209 runs",
    /// "Bulls won by 7 wkts (4b rem)". Before the start it's only "Starts at 19:15 local
    /// time", which the row's own clock already says.
    var cricketSummary: String? {
        strStatus == "pre" ? nil : cricket?.summary
    }

    /// "1st T20I · England tour of Australia 2026/27", for a row's context line.
    var cricketContext: String? {
        let parts = [round, tournamentName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Compact surfaces (widgets, watch, menu bar)

public extension Game {
    /// A side's score for a tight space. Every sport but cricket: the score as sent.
    /// Cricket: just the latest innings ("144/2"), since "137 & 144/2 (40 ov)" won't fit.
    func compactScore(home: Bool) -> String? {
        guard isCricket else { return home ? intHomeScore : intAwayScore }
        let side: GameSituation.Side = home ? .home : .away
        if let last = cricket?.innings(for: side).last { return last.scoreText }
        return cricketScore(for: side)
    }

    /// Whether `home` is ahead (live) or won (final), for bolding. Cricket asks ESPN,
    /// since runs don't decide a rain-affected match.
    func isAhead(home: Bool) -> Bool {
        if isCricket { return cricketWinner == (home ? .home : .away) }
        guard let homeScore = intHomeScore.flatMap({ Int($0) }),
              let awayScore = intAwayScore.flatMap({ Int($0) }) else { return false }
        return home ? homeScore > awayScore : awayScore > homeScore
    }
}
