//
//  CustomAlerts.swift
//  SportsCalModel
//
//  Pro custom live alerts ("Player Alerts" + "Game Alerts"): the rules an install
//  registers with `POST /notifications/custom`, the server's answer, the free-tier
//  cap, and the pure pieces the server's `CustomAlertJob` decides with (which plays
//  count as which play type, milestone values, the "close game" and "final period"
//  filters, alert copy). Shared so the app builds rules with the same vocabulary the
//  server matches on.
//
//  Wording: milestone language only ("reaches 30 points", "hits a home run"). Never
//  betting terms (over/under, line, prop, total).
//
//  v1 sports: player plays for NBA, MLB, NHL and soccer; milestones for NBA, MLB and
//  NHL; game situations (`ClutchMoment`) for NBA, MLB, NHL and NFL. NFL and college
//  player alerts are off.
//

import Foundation

// MARK: - Play types

/// What a player-play rule listens for. Unknown raw values (a newer app) are dropped
/// when decoding, never fatal.
public enum AlertPlayType: String, Codable, CaseIterable, Hashable, Sendable {
    // Basketball
    /// A made three-pointer.
    case threePointer
    /// A made dunk.
    case dunk
    /// Any made field goal.
    case basket
    /// Basketball, hockey and soccer: an assist on a score.
    case assist
    case block
    case steal
    // Baseball
    case homeRun
    /// A single, double, triple or home run.
    case hit
    /// A strikeout recorded by the pitcher.
    case strikeout
    // Hockey and soccer
    case goal
    /// Hockey: a goal or an assist.
    case point
    // Soccer
    case yellowCard
    case redCard

    /// The sports this play type applies to.
    public var sports: Set<SportType> {
        switch self {
        case .threePointer, .dunk, .basket, .block, .steal: return [.basketball]
        case .assist: return [.basketball, .hockey, .soccer]
        case .homeRun, .hit, .strikeout: return [.mlb]
        case .goal: return [.hockey, .soccer]
        case .point: return [.hockey]
        case .yellowCard, .redCard: return [.soccer]
        }
    }

    /// The play types offered for a sport, in display order.
    public static func types(for sport: SportType) -> [AlertPlayType] {
        allCases.filter { $0.sports.contains(sport) }
    }

    /// For the alert builder's chips: "3-pointers", "Home runs".
    public var title: String {
        switch self {
        case .threePointer: return "3-pointers"
        case .dunk: return "Dunks"
        case .basket: return "Baskets"
        case .assist: return "Assists"
        case .block: return "Blocks"
        case .steal: return "Steals"
        case .homeRun: return "Home runs"
        case .hit: return "Hits"
        case .strikeout: return "Strikeouts"
        case .goal: return "Goals"
        case .point: return "Points (goals + assists)"
        case .yellowCard: return "Yellow cards"
        case .redCard: return "Red cards"
        }
    }

    /// The verb phrase for an alert title: "Stephen Curry hits a 3-pointer".
    public func phrase(sport: SportType) -> String {
        switch self {
        case .threePointer: return "hits a 3-pointer"
        case .dunk: return "throws down a dunk"
        case .basket: return "scores"
        case .assist: return sport == .soccer ? "sets up a goal" : "picks up an assist"
        case .block: return "blocks a shot"
        case .steal: return "comes up with a steal"
        case .homeRun: return "hits a home run"
        case .hit: return "gets a hit"
        case .strikeout: return "records a strikeout"
        case .goal: return "scores a goal"
        case .point: return "picks up a point"
        case .yellowCard: return "is shown a yellow card"
        case .redCard: return "is sent off"
        }
    }
}

/// One athlete's part in one play, as the alert job matches it: "athlete 3975 made a
/// three-pointer in play 401…".
public struct PlayHighlight: Codable, Equatable, Hashable, Sendable {
    public var athleteID: String
    public var type: AlertPlayType
    /// The play's own period (quarter, inning, half), where known.
    public var period: Int?

    public init(athleteID: String, type: AlertPlayType, period: Int? = nil) {
        self.athleteID = athleteID
        self.type = type
        self.period = period
    }
}

public extension PlayHighlight {
    /// The play types each athlete in an ESPN play earned.
    ///
    /// - Parameters:
    ///   - play: One ESPN play with `participants` (basketball, baseball, hockey).
    ///   - sport: The game's sport.
    ///   - fullNames: Athlete ID → full display name ("Stephen Curry"), from the box
    ///     score. Basketball plays carry no participant roles; a block's text names
    ///     the blocker first ("Rudy Gobert blocks …"), so the name decides who.
    static func highlights(in play: Play, sport: SportType, fullNames: [String: String] = [:]) -> [PlayHighlight] {
        guard let participants = play.participants, !participants.isEmpty else { return [] }
        let text = (play.text ?? "").lowercased()
        let typeText = (play.type?.text ?? "").lowercased()
        let period = play.period?.number
        var out: [PlayHighlight] = []
        func add(_ athleteID: String?, _ type: AlertPlayType) {
            guard let athleteID, !out.contains(where: { $0.athleteID == athleteID && $0.type == type }) else { return }
            out.append(PlayHighlight(athleteID: athleteID, type: type, period: period))
        }

        switch sport {
        case .basketball:
            // ESPN lists basketball participants without roles: the shooter (or the
            // player who lost the ball) first, then the assister (or the stealer).
            let first = participants.first?.athleteID
            let second = participants.count > 1 ? participants[1].athleteID : nil
            let isFreeThrow = typeText.contains("free throw") || text.contains("free throw")
            if play.scoringPlay == true, !isFreeThrow {
                add(first, .basket)
                if text.contains("three point") || text.contains("3-pt") { add(first, .threePointer) }
                if typeText.contains("dunk") || text.contains("dunk") { add(first, .dunk) }
                if text.contains("assist") { add(second, .assist) }
            }
            if text.contains(" steals") || text.contains("steal)") { add(second, .steal) }
            if text.contains(" blocks ") {
                let byName = participants.first { participant in
                    guard let name = fullNames[participant.athleteID]?.lowercased(), !name.isEmpty else { return false }
                    return text.contains("\(name) blocks ")
                }
                add(byName?.athleteID ?? participants.last?.athleteID, .block)
            }
        case .mlb:
            let batter = participants.first { $0.role == "batter" }?.athleteID
            let pitcher = participants.first { $0.role == "pitcher" }?.athleteID
            let homered = text.contains("homered") || text.contains("home run") || text.contains("grand slam")
            if homered { add(batter, .homeRun) }
            if homered || text.contains("singled") || text.contains("doubled") || text.contains("tripled") {
                add(batter, .hit)
            }
            if text.contains("struck out") { add(pitcher, .strikeout) }
        case .hockey:
            let isGoal = typeText == "goal" || (play.scoringPlay == true && typeText != "shootout")
            guard isGoal else { break }
            for participant in participants {
                switch participant.role {
                case "scorer":
                    add(participant.athleteID, .goal)
                    add(participant.athleteID, .point)
                case "assister":
                    add(participant.athleteID, .assist)
                    add(participant.athleteID, .point)
                default: break
                }
            }
        case .soccer, .nfl, .golf, .tennis, .racing, .cricket:
            break
        }
        return out
    }

    /// The play types each athlete in a soccer key event earned. Needs the event's
    /// `athleteIDs` ([scorer, assister] for a goal; [player] for a card).
    static func highlights(in event: SoccerMatchEvent) -> [PlayHighlight] {
        guard let ids = event.athleteIDs, let first = ids.first, !first.isEmpty else { return [] }
        switch event.type {
        case .goal:
            var out = [PlayHighlight(athleteID: first, type: .goal, period: event.period)]
            if ids.count > 1, !ids[1].isEmpty, ids[1] != first {
                out.append(PlayHighlight(athleteID: ids[1], type: .assist, period: event.period))
            }
            return out
        case .penaltyGoal:
            return [PlayHighlight(athleteID: first, type: .goal, period: event.period)]
        case .yellowCard:
            return [PlayHighlight(athleteID: first, type: .yellowCard, period: event.period)]
        case .redCard:
            return [PlayHighlight(athleteID: first, type: .redCard, period: event.period)]
        case .ownGoal, .penaltyMissed, .substitution, .other:
            return []
        }
    }
}

// MARK: - Milestones

/// "Reaches `threshold` `stat`": fires once per game, the first time the player's
/// live number goes from below the threshold to at or above it.
public struct AlertMilestone: Codable, Equatable, Hashable, Sendable {
    /// A `PlayerLiveStatLine.stats` key (`points`, `batting.homeRuns`,
    /// `pitching.strikeouts`, `goals`), or a derived one: `doubleDouble`,
    /// `tripleDouble` (1 when reached, else 0).
    public var stat: String
    public var threshold: Double

    public init(stat: String, threshold: Double) {
        self.stat = stat
        self.threshold = threshold
    }

    public static let doubleDouble = "doubleDouble"
    public static let tripleDouble = "tripleDouble"

    /// The player's current value for `stat`, nil if the line doesn't have it.
    public static func value(of stat: String, in stats: [String: Double]) -> Double? {
        switch stat {
        case doubleDouble, tripleDouble:
            let categories = ["points", "rebounds", "assists", "steals", "blocks"]
            guard stats["points"] != nil else { return nil }
            let tens = categories.filter { (stats[$0] ?? 0) >= 10 }.count
            return tens >= (stat == tripleDouble ? 3 : 2) ? 1 : 0
        default:
            return stats[stat]
        }
    }

    public func value(in stats: [String: Double]) -> Double? { Self.value(of: stat, in: stats) }

    /// Whether going from `previous` to `current` crosses the threshold.
    public func isCrossed(from previous: Double?, to current: Double?) -> Bool {
        guard let previous, let current else { return false }
        return previous < threshold && current >= threshold
    }

    /// A ready-made milestone the alert builder offers.
    public struct Preset: Equatable, Hashable, Sendable {
        public var stat: String
        /// "points".
        public var label: String
        /// Stepper starting points, e.g. 20 / 30 / 40.
        public var suggested: [Double]
    }

    /// Ready-made milestones per sport. Any `PlayerLiveStatLine` key is also accepted.
    public static func presets(for sport: SportType) -> [Preset] {
        switch sport {
        case .basketball:
            return [
                Preset(stat: "points", label: "points", suggested: [20, 30, 40, 50]),
                Preset(stat: "rebounds", label: "rebounds", suggested: [10, 15, 20]),
                Preset(stat: "assists", label: "assists", suggested: [10, 15]),
                Preset(stat: "threePointFieldGoalsMade", label: "3-pointers", suggested: [5, 8, 10]),
                Preset(stat: "blocks", label: "blocks", suggested: [3, 5]),
                Preset(stat: "steals", label: "steals", suggested: [3, 5]),
                Preset(stat: doubleDouble, label: "a double-double", suggested: [1]),
                Preset(stat: tripleDouble, label: "a triple-double", suggested: [1]),
            ]
        case .mlb:
            return [
                Preset(stat: "pitching.strikeouts", label: "strikeouts", suggested: [8, 10, 12]),
                Preset(stat: "batting.homeRuns", label: "home runs", suggested: [2, 3]),
                Preset(stat: "batting.hits", label: "hits", suggested: [3, 4]),
                Preset(stat: "batting.RBIs", label: "RBIs", suggested: [3, 4, 5]),
            ]
        case .hockey:
            return [
                Preset(stat: "goals", label: "goals", suggested: [2, 3]),
                Preset(stat: "assists", label: "assists", suggested: [2, 3]),
                Preset(stat: "points", label: "points", suggested: [3, 4]),
                Preset(stat: "saves", label: "saves", suggested: [30, 40]),
            ]
        case .soccer, .nfl, .golf, .tennis, .racing, .cricket:
            return []
        }
    }

    /// "30 points", "a triple-double", "10 strikeouts".
    public func description(sport: SportType) -> String {
        let preset = Self.presets(for: sport).first { $0.stat == stat }
        if stat == Self.doubleDouble || stat == Self.tripleDouble {
            return preset?.label ?? stat
        }
        let label = preset?.label ?? Self.humanized(stat)
        let number = threshold.rounded() == threshold ? String(Int(threshold)) : String(threshold)
        return "\(number) \(label)"
    }

    /// `batting.RBIs` → "RBIs", `threePointFieldGoalsMade` → "three point field goals made".
    static func humanized(_ key: String) -> String {
        let last = key.split(separator: ".").last.map(String.init) ?? key
        guard last.contains(where: \.isLowercase) else { return last }
        var words = ""
        for character in last {
            if character.isUppercase, !words.isEmpty { words.append(" ") }
            words.append(character)
        }
        return words.lowercased()
    }
}

// MARK: - Rules

/// One custom alert rule. The server drops rules it can't use (unknown kind or sport,
/// missing athlete) instead of failing the registration.
public struct AlertRule: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        /// "Every 3-pointer by Steph Curry".
        case playerPlay
        /// "Jokić reaches a triple-double".
        case playerMilestone
        /// "Any NBA game in crunch time" (a `ClutchMoment`), without a Live Activity.
        case gameSituation
    }

    /// Client-made, stable across syncs (a UUID string). At most 64 characters.
    public var id: String
    public var kind: Kind
    public var sport: SportType
    /// ESPN athlete ID (the box score's / `PlayParticipant.athleteID`). Player kinds only.
    public var athleteID: String?
    /// Full name for alert copy: "Stephen Curry".
    public var athleteName: String?
    /// The team as the app's `Game` carries it (`idHomeTeam` / `idAwayTeam`, i.e.
    /// TheSportsDB IDs where the schedule has them). Required for player kinds: it's
    /// how the server finds the player's live game. Optional for situations: nil means
    /// every game of the sport's main league (NBA, MLB, NHL, NFL).
    public var teamID: String?
    /// `playerPlay`: which plays. Unknown values are dropped.
    public var playTypes: [AlertPlayType]?
    /// `playerMilestone`.
    public var milestone: AlertMilestone?
    /// `gameSituation`: one `ClutchMoment` kind, or nil for any of them.
    public var situation: ClutchMoment.Kind?
    /// Only in the final period (4th quarter, 3rd period, 9th inning, second half) or later.
    public var finalPeriodOnly: Bool
    /// Only when the game is close (see `AlertRule.isClose`).
    public var closeGameOnly: Bool

    public init(
        id: String,
        kind: Kind,
        sport: SportType,
        athleteID: String? = nil,
        athleteName: String? = nil,
        teamID: String? = nil,
        playTypes: [AlertPlayType]? = nil,
        milestone: AlertMilestone? = nil,
        situation: ClutchMoment.Kind? = nil,
        finalPeriodOnly: Bool = false,
        closeGameOnly: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.sport = sport
        self.athleteID = athleteID
        self.athleteName = athleteName
        self.teamID = teamID
        self.playTypes = playTypes
        self.milestone = milestone
        self.situation = situation
        self.finalPeriodOnly = finalPeriodOnly
        self.closeGameOnly = closeGameOnly
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, sport, athleteID, athleteName, teamID, playTypes, milestone, situation, finalPeriodOnly, closeGameOnly
    }

    /// Strict on what the rule can't work without (id, kind, sport); lenient on the rest.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        let sportRaw = try c.decode(String.self, forKey: .sport)
        guard let sport = SportType(rawValue: sportRaw) else {
            throw DecodingError.dataCorruptedError(forKey: .sport, in: c, debugDescription: "Unknown sport \(sportRaw)")
        }
        self.sport = sport
        athleteID = (try? c.decodeIfPresent(String.self, forKey: .athleteID)) ?? nil
        athleteName = (try? c.decodeIfPresent(String.self, forKey: .athleteName)) ?? nil
        teamID = (try? c.decodeIfPresent(String.self, forKey: .teamID)) ?? nil
        let rawTypes = (try? c.decodeIfPresent([String].self, forKey: .playTypes)) ?? nil
        playTypes = rawTypes.map { $0.compactMap(AlertPlayType.init(rawValue:)) }
        milestone = (try? c.decodeIfPresent(AlertMilestone.self, forKey: .milestone)) ?? nil
        situation = (try? c.decodeIfPresent(String.self, forKey: .situation))?.flatMap(ClutchMoment.Kind.init(rawValue:))
        finalPeriodOnly = (try? c.decodeIfPresent(Bool.self, forKey: .finalPeriodOnly)) ?? false
        closeGameOnly = (try? c.decodeIfPresent(Bool.self, forKey: .closeGameOnly)) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(sport.rawValue, forKey: .sport)
        try c.encodeIfPresent(athleteID, forKey: .athleteID)
        try c.encodeIfPresent(athleteName, forKey: .athleteName)
        try c.encodeIfPresent(teamID, forKey: .teamID)
        try c.encodeIfPresent(playTypes, forKey: .playTypes)
        try c.encodeIfPresent(milestone, forKey: .milestone)
        try c.encodeIfPresent(situation, forKey: .situation)
        try c.encode(finalPeriodOnly, forKey: .finalPeriodOnly)
        try c.encode(closeGameOnly, forKey: .closeGameOnly)
    }

    public var isPlayerRule: Bool { kind != .gameSituation }

    /// Sports with player-play rules in v1.
    public static let playerPlaySports: Set<SportType> = [.basketball, .mlb, .hockey, .soccer]
    /// Sports with milestone rules in v1 (soccer has no live player box score).
    public static let milestoneSports: Set<SportType> = [.basketball, .mlb, .hockey]
    /// Sports `ClutchMoment` covers.
    public static let situationSports: Set<SportType> = [.basketball, .mlb, .hockey, .nfl]

    /// The leagues player rules follow in v1 (NBA, MLB, NHL, any soccer league; no
    /// WNBA or college). Situations without a team follow the main league only.
    public static func isPlayerAlertLeague(_ league: Leagues?, sport: SportType) -> Bool {
        guard let league else { return false }
        switch sport {
        case .basketball: return league == .nba
        case .mlb: return league == .mlb
        case .hockey: return league == .nhl
        case .soccer: return league.isSoccer
        case .nfl, .golf, .tennis, .racing, .cricket: return false
        }
    }

    public static func mainLeague(for sport: SportType) -> Leagues? {
        switch sport {
        case .basketball: return .nba
        case .mlb: return .mlb
        case .hockey: return .nhl
        case .nfl: return .nfl
        case .soccer, .golf, .tennis, .racing, .cricket: return nil
        }
    }

    /// Whether the server can act on this rule.
    public var isValid: Bool {
        guard !id.isEmpty, id.count <= 64 else { return false }
        if let teamID, teamID.isEmpty || teamID.count > 32 { return false }
        switch kind {
        case .playerPlay:
            guard Self.playerPlaySports.contains(sport), hasAthleteAndTeam,
                  let types = playTypes, !types.isEmpty,
                  types.allSatisfy({ $0.sports.contains(sport) }) else { return false }
            return true
        case .playerMilestone:
            guard Self.milestoneSports.contains(sport), hasAthleteAndTeam, let milestone,
                  !milestone.stat.isEmpty, milestone.stat.count <= 64,
                  milestone.threshold > 0, milestone.threshold.isFinite else { return false }
            return true
        case .gameSituation:
            return Self.situationSports.contains(sport)
        }
    }

    private var hasAthleteAndTeam: Bool {
        guard let athleteID, !athleteID.isEmpty, athleteID.count <= 32, teamID != nil else { return false }
        return true
    }

    /// Whether `filters` let an alert through right now.
    /// - Parameters:
    ///   - period: The current period (or the play's own).
    ///   - margin: The absolute score difference.
    ///   - league: Sets the period structure; defaults per sport.
    public func passesFilters(period: Int?, margin: Int, league: Leagues?) -> Bool {
        if finalPeriodOnly {
            guard let period, period >= Self.finalPeriod(sport: sport, league: league) else { return false }
        }
        if closeGameOnly, !Self.isClose(sport: sport, margin: margin) { return false }
        return true
    }

    /// The final regulation period: 4th quarter, 3rd period, 9th inning, second half.
    public static func finalPeriod(sport: SportType, league: Leagues?) -> Int {
        if let periods = (league ?? mainLeague(for: sport))?.regulationPeriods { return periods }
        switch sport {
        case .soccer: return 2
        case .hockey: return 3
        case .mlb: return 9
        default: return 4
        }
    }

    /// "Close game": within one possession-ish per sport. Basketball 8, football 8,
    /// baseball 2 runs, hockey and soccer 1 goal.
    public static func isClose(sport: SportType, margin: Int) -> Bool {
        switch sport {
        case .basketball, .nfl: return margin <= 8
        case .mlb: return margin <= 2
        case .hockey, .soccer: return margin <= 1
        case .golf, .tennis, .racing, .cricket: return true
        }
    }
}

// MARK: - Limits

/// How many rules an install may have. Free: one player with one rule (and no game
/// situations); Pro: effectively unlimited, with a ceiling against abuse.
public struct CustomAlertLimits: Codable, Equatable, Hashable, Sendable {
    public var maxPlayers: Int
    public var maxRules: Int
    public var allowsSituations: Bool

    public init(maxPlayers: Int, maxRules: Int, allowsSituations: Bool) {
        self.maxPlayers = maxPlayers
        self.maxRules = maxRules
        self.allowsSituations = allowsSituations
    }

    public static let free = CustomAlertLimits(maxPlayers: 1, maxRules: 1, allowsSituations: false)
    public static let pro = CustomAlertLimits(maxPlayers: 50, maxRules: 100, allowsSituations: true)

    public static func limits(isPro: Bool) -> CustomAlertLimits { isPro ? .pro : .free }

    /// The rules this tier keeps, in the order given, and the IDs of the ones it drops
    /// (invalid, duplicate ID, or over the cap).
    public func apply(to rules: [AlertRule]) -> (accepted: [AlertRule], droppedIDs: [String]) {
        var accepted: [AlertRule] = []
        var dropped: [String] = []
        var players: [String] = []
        var ids = Set<String>()
        for rule in rules {
            guard rule.isValid, !ids.contains(rule.id), accepted.count < maxRules else {
                dropped.append(rule.id)
                continue
            }
            if rule.kind == .gameSituation {
                guard allowsSituations else { dropped.append(rule.id); continue }
            } else if let athlete = rule.athleteID, !players.contains(athlete) {
                guard players.count < maxPlayers else { dropped.append(rule.id); continue }
                players.append(athlete)
            }
            ids.insert(rule.id)
            accepted.append(rule)
        }
        return (accepted, dropped)
    }
}

// MARK: - Registration

/// `POST /notifications/custom`: replaces the install's whole rule set. The install
/// is the `X-Install-ID` header (as for soccer alerts). An empty `rules` unregisters.
public struct CustomAlertRegistration: Codable, Equatable, Sendable {
    /// APNS device token (hex).
    public var token: String
    /// RevenueCat app user ID (`Purchases.shared.appUserID`); the server checks the
    /// `Pro` entitlement with it. Missing → treated as free.
    public var revenueCatAppUserID: String?
    /// True for a sandbox APNS token (Xcode builds). Nil falls back to the
    /// `X-APNS-Env` header, then the server's own environment.
    public var sandbox: Bool?
    /// Rules that don't decode (unknown kind or sport) are skipped, not fatal.
    public var rules: [AlertRule]

    public init(token: String, revenueCatAppUserID: String?, sandbox: Bool? = nil, rules: [AlertRule]) {
        self.token = token
        self.revenueCatAppUserID = revenueCatAppUserID
        self.sandbox = sandbox
        self.rules = rules
    }

    enum CodingKeys: String, CodingKey { case token, revenueCatAppUserID, sandbox, rules }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decode(String.self, forKey: .token)
        revenueCatAppUserID = (try? c.decodeIfPresent(String.self, forKey: .revenueCatAppUserID)) ?? nil
        sandbox = (try? c.decodeIfPresent(Bool.self, forKey: .sandbox)) ?? nil
        let lossy = (try? c.decodeIfPresent([LossyRule].self, forKey: .rules)) ?? nil
        rules = (lossy ?? []).compactMap(\.value)
    }

    private struct LossyRule: Decodable {
        let value: AlertRule?
        init(from decoder: Decoder) throws { value = try? AlertRule(from: decoder) }
    }
}

/// The server's answer to `POST /notifications/custom`.
public struct CustomAlertRegistrationResponse: Codable, Equatable, Sendable {
    /// The rules the server will act on (the free cap applied).
    public var rules: [AlertRule]
    /// Rules it won't: invalid, duplicate, or over this tier's cap.
    public var droppedRuleIDs: [String]
    /// Whether the server verified the `Pro` entitlement with RevenueCat.
    public var isPro: Bool
    public var limits: CustomAlertLimits

    public init(rules: [AlertRule], droppedRuleIDs: [String], isPro: Bool, limits: CustomAlertLimits) {
        self.rules = rules
        self.droppedRuleIDs = droppedRuleIDs
        self.isPro = isPro
        self.limits = limits
    }
}

/// `POST /notifications/custom/mute`: the "Mute this player for this game" action.
/// With `athleteID`, every rule about that player goes quiet for `eventID`; without
/// it, only `ruleID` does. Lasts 24 hours.
public struct CustomAlertMuteRequest: Codable, Equatable, Sendable {
    public var token: String
    public var eventID: String
    public var ruleID: String?
    public var athleteID: String?
    public var sandbox: Bool?

    public init(token: String, eventID: String, ruleID: String? = nil, athleteID: String? = nil, sandbox: Bool? = nil) {
        self.token = token
        self.eventID = eventID
        self.ruleID = ruleID
        self.athleteID = athleteID
        self.sandbox = sandbox
    }
}

// MARK: - Notification contract

/// The push a custom alert arrives as, for the app's notification handling.
///
/// - `aps.category` is `category`. Register a `UNNotificationCategory` with that
///   identifier and two actions: `muteActionID` ("Mute this player for this game":
///   call `POST /notifications/custom/mute` with `eventID` + `athleteID`) and
///   `turnOffActionID` ("Turn off this alert": remove `ruleID` locally and re-sync
///   `POST /notifications/custom`). Situation alerts have no athlete: show only
///   "Turn off this alert" for them (`type` is `custom_situation`).
/// - Custom payload keys: `eventID` (the live game's id, which a tap opens), `type`
///   (`custom_play`, `custom_milestone`, `custom_situation`), `ruleID`, and
///   `athleteID` for player alerts.
/// - `thread-id` is the event ID, so a run of alerts from one game stacks.
public enum CustomAlertNotification {
    public static let category = "CUSTOM_ALERT"
    public static let muteActionID = "CUSTOM_ALERT_MUTE_PLAYER_GAME"
    public static let turnOffActionID = "CUSTOM_ALERT_TURN_OFF"

    public static let eventIDKey = "eventID"
    public static let typeKey = "type"
    public static let ruleIDKey = "ruleID"
    public static let athleteIDKey = "athleteID"

    public static let playType = "custom_play"
    public static let milestoneType = "custom_milestone"
    public static let situationType = "custom_situation"

    /// Most custom alerts one install gets for one game.
    public static let maxPerDevicePerGame = 15
}
