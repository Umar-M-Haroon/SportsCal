//
//  SoccerPresentation.swift
//  SportsCalModel
//
//  How a soccer match reads, where it differs from a US game: the home side comes
//  first ("Arsenal vs Chelsea", home on the left / top), a level match can be won on
//  penalties, a two-leg tie has an aggregate, and a row shows who scored and who was
//  sent off. Every surface asks these helpers instead of checking the sport itself.
//
//  The match centre's goal / card timeline (dividers, running score, the shootout)
//  is built here too, so it can be tested without a view.
//

import Foundation

// MARK: - Order

public extension Game {
    /// Home team first, on the left / top. Soccer's convention everywhere, MLS
    /// included; US sports keep away first ("Away @ Home").
    var displaysHomeFirst: Bool { sportType == .soccer }

    /// The two sides in display order: `(first, second)` is (home, away) for soccer,
    /// (away, home) elsewhere.
    func displayOrdered<T>(home: T, away: T) -> (first: T, second: T) {
        displaysHomeFirst ? (home, away) : (away, home)
    }

    /// The sides in display order.
    var displayedSides: (first: GameSituation.Side, second: GameSituation.Side) {
        displayOrdered(home: .home, away: .away)
    }

    /// "Arsenal vs Chelsea" for soccer; "Celtics @ Lakers" elsewhere, or "vs" at a
    /// neutral site. Notifications, share sheets and calendar events use it.
    var matchupTitle: String { matchupTitle(home: strHomeTeam, away: strAwayTeam) }

    func matchupTitle(home: String, away: String) -> String {
        if displaysHomeFirst { return "\(home) vs \(away)" }
        let separator = playoff?.isNeutralSite == true ? " vs " : " @ "
        return away + separator + home
    }
}

// MARK: - Winner, shootout, aggregate

/// A score pair by side.
public struct SoccerScore: Equatable, Hashable, Sendable {
    public var home: Int
    public var away: Int

    public init(home: Int, away: Int) {
        self.home = home
        self.away = away
    }

    public subscript(side: GameSituation.Side) -> Int {
        get { side == .home ? home : away }
        set { if side == .home { home = newValue } else { away = newValue } }
    }

    /// "2–1", in the game's display order.
    public func text(for game: Game) -> String {
        let (first, second) = game.displayOrdered(home: home, away: away)
        return "\(first)–\(second)"
    }
}

public extension Game {
    /// The side that won (or leads), taking ESPN's winner first: it's the only thing
    /// that knows a level match went to the side that won the shootout. Nil for a
    /// draw, or before a score.
    var winningSide: GameSituation.Side? {
        if homeWinner == true { return .home }
        if awayWinner == true { return .away }
        guard let home = Int(intHomeScore ?? ""), let away = Int(intAwayScore ?? "") else { return nil }
        if home != away { return home > away ? .home : .away }
        // Level, mid-shootout: whoever is ahead on penalties.
        if let shootout = shootoutScore, shootout.home != shootout.away {
            return shootout.home > shootout.away ? .home : .away
        }
        return nil
    }

    /// Penalty-shootout goals. Soccer only (hockey shootouts don't read "pens").
    var shootoutScore: SoccerScore? {
        guard sportType == .soccer, let home = homeShootoutScore, let away = awayShootoutScore,
              home + away > 0 else { return nil }
        return SoccerScore(home: home, away: away)
    }

    /// "4–3 pens", home first.
    var shootoutLine: String? {
        shootoutScore.map { "\($0.text(for: self)) pens" }
    }

    /// A two-leg tie's aggregate goals. Older servers only send `aggregateScore`'s
    /// text ("Agg: 2-3", away first), so that's read as a fallback.
    var aggregateGoals: SoccerScore? {
        guard sportType == .soccer else { return nil }
        if let home = scoreboardExtras?.homeAggregate, let away = scoreboardExtras?.awayAggregate {
            return SoccerScore(home: home, away: away)
        }
        let numbers = (aggregateScore ?? "").split { !$0.isNumber }.compactMap { Int($0) }
        guard numbers.count == 2 else { return nil }
        return SoccerScore(home: numbers[1], away: numbers[0])
    }

    /// "Agg 3–2", in display order.
    var aggregateLine: String? {
        aggregateGoals.map { "Agg \($0.text(for: self))" }
    }

    /// "Arsenal won 4–3 on penalties" / "Chelsea lead 3–2 on aggregate", for VoiceOver.
    func soccerDecisionSpoken(homeName: String, awayName: String) -> String? {
        func name(_ side: GameSituation.Side) -> String { side == .home ? homeName : awayName }
        var parts: [String] = []
        if let shootout = shootoutScore {
            let leader: GameSituation.Side = shootout.home >= shootout.away ? .home : .away
            let done = hasDoneStatus || isCompleted == true
            parts.append("\(name(leader)) \(done ? "won" : "lead") \(shootout[leader])–\(shootout[leader.opposite]) on penalties")
        }
        if let aggregate = aggregateGoals {
            if aggregate.home == aggregate.away {
                parts.append("\(aggregate.home)–\(aggregate.away) on aggregate")
            } else {
                let leader: GameSituation.Side = aggregate.home > aggregate.away ? .home : .away
                parts.append("\(name(leader)) \(aggregate[leader])–\(aggregate[leader.opposite]) on aggregate")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - Scorers and cards on a row

public extension Game {
    /// Red cards shown to one side so far.
    func redCards(_ side: GameSituation.Side) -> Int {
        (soccerDetails ?? []).filter { $0.kind == .redCard && $0.side == side }.count
    }

    /// One side's goals for a list row: "Saka 12', 67' · Mac Allister 45'+2' (P)".
    /// Own goals sit with the side they counted for, as ESPN files them. Nil
    /// without a goal.
    func scorerLine(_ side: GameSituation.Side) -> String? {
        var order: [String] = []
        var minutes: [String: [String]] = [:]
        for incident in soccerDetails ?? [] where incident.side == side {
            let note: String
            switch incident.kind {
            case .goal: note = ""
            case .penaltyGoal: note = " (P)"
            case .ownGoal: note = " (OG)"
            default: continue
            }
            let name = Self.rowName(incident.athlete) ?? "Goal"
            if minutes[name] == nil { order.append(name) }
            minutes[name, default: []].append((incident.clock ?? "") + note)
        }
        guard !order.isEmpty else { return nil }
        return order.map { name in
            let marks = (minutes[name] ?? []).filter { !$0.isEmpty }
            return marks.isEmpty ? name : "\(name) \(marks.joined(separator: ", "))"
        }.joined(separator: " · ")
    }

    /// A player's name as a row has room for: the given name dropped, so "Alexis Mac
    /// Allister" reads "Mac Allister" and "Rodri" stays "Rodri".
    static func rowName(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        let parts = name.split(separator: " ")
        return parts.count > 1 ? parts.dropFirst().joined(separator: " ") : name
    }

    /// The current period of a live match, from the clock: 1 and 2 are the halves,
    /// 3 and 4 extra time. "HT" counts as the second half's turn. Nil when the clock
    /// doesn't say.
    var soccerClockPeriod: Int? {
        guard sportType == .soccer else { return nil }
        let progress = (strProgress ?? "").trimmingCharacters(in: .whitespaces)
        if progress.uppercased() == "HT" || strStatus?.uppercased() == "HT" { return 2 }
        // "67'", "45'+2'", "90'+5'": the first number is the minute of the period.
        guard let minute = progress.split(whereSeparator: { !$0.isNumber }).first.flatMap({ Int($0) }) else { return nil }
        switch minute {
        case ...45: return 1
        case 46...90: return 2
        case 91...105: return 3
        default: return 4
        }
    }
}

// MARK: - Matchday

public extension Game {
    /// The league matchday ("Matchday 12"), from TheSportsDB's round. Nil for cups,
    /// whose rounds aren't matchdays, for a round outside a season's range, and for
    /// games ESPN added (they carry no round).
    var soccerMatchday: Int? {
        guard sportType == .soccer, let league = knownLeagueForRound, !league.isSoccerCup,
              let round = sportsDBRound, (1...60).contains(round) else { return nil }
        return round
    }

    private var knownLeagueForRound: Leagues? {
        idLeague.flatMap { Int($0) }.flatMap(Leagues.init(rawValue:))
    }
}

public extension Leagues {
    /// Knockout cups and tournaments: no table of matchdays.
    var isSoccerCup: Bool {
        switch self {
        case .FA_Cup, .Copa_del_Rey, .Coupe_De_France, .DFB_Pokal, .FIFA_World_Cup, .Womens_World_Cup, .Copa_America:
            return true
        default:
            return false
        }
    }
}

// MARK: - Competition order

public extension Leagues {
    /// Where a soccer competition sorts among others: the top flights and the
    /// Champions League first, cups last. Nil for leagues not ranked (and every other
    /// sport). Browse chips and the day page's competition groups share it.
    var soccerDisplayRank: Int? { Self.soccerOrder[self] }

    /// The name a row or group heading has room for: "Premier League", "Champions
    /// League". Falls back to `leagueName`.
    var soccerShortName: String {
        switch self {
        case .English_Premier_League: return "Premier League"
        case .English_League_Championship: return "Championship"
        case .UEFA_Champions_League: return "Champions League"
        case .UEFA_Europa_League: return "Europa League"
        case .UEFA_Conference_League: return "Conference League"
        case .UEFA_Nations_League: return "Nations League"
        case .FIFA_World_Cup: return "World Cup"
        case .Womens_World_Cup: return "Women's World Cup"
        default: return leagueName
        }
    }

    private static let soccerOrder: [Leagues: Int] = {
        let order: [Leagues] = [
            .English_Premier_League, .La_Liga, .UEFA_Champions_League, .German_Bundesliga, .Serie_A,
            .Ligue_1, .MLS, .FIFA_World_Cup, .Womens_World_Cup, .UEFA_Europa_League,
            .UEFA_Conference_League, .Liga_MX, .Eredivisie, .A_League, .English_League_Championship,
            .UEFA_Nations_League, .Copa_America, .FA_Cup, .Copa_del_Rey, .DFB_Pokal, .Coupe_De_France,
        ]
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
    }()
}

// MARK: - Match centre timeline

/// One line of the match centre's events timeline.
public enum SoccerTimelineRow: Equatable, Identifiable {
    /// A goal, card or substitution. `score` is the score after it, on goals only.
    case event(SoccerMatchEvent, score: SoccerScore?)
    /// "HT", "90'", "ET HT", "FT", "AET", with the score at that point when known.
    case divider(label: String, score: SoccerScore?)
    /// The shootout's heading, with its tally.
    case shootoutHeader(score: SoccerScore?)
    /// One shootout kick, with the tally after it.
    case shootoutKick(SoccerShootoutKick, tally: SoccerScore)

    public var id: String {
        switch self {
        case .event(let event, _): return "e-\(event.id)"
        case .divider(let label, _): return "d-\(label)"
        case .shootoutHeader: return "pens"
        case .shootoutKick(let kick, _): return "k-\(kick.id)"
        }
    }
}

public struct SoccerShootoutKick: Equatable, Hashable, Sendable {
    public var id: String
    public var side: GameSituation.Side
    public var player: String?
    public var scored: Bool

    public init(id: String, side: GameSituation.Side, player: String?, scored: Bool) {
        self.id = id
        self.side = side
        self.player = player
        self.scored = scored
    }
}

public enum SoccerTimeline {
    /// The timeline, oldest first: in-play events split by period with HT / 90' /
    /// extra-time dividers, a running score on each goal, a closing FT / AET line, and
    /// the shootout grouped at the end.
    ///
    /// - Parameters:
    ///   - events: the match centre's events (periods 1–4; 5 is the shootout).
    ///   - shootoutDetails: the scoreboard's goals and cards. ESPN's match summary
    ///     only says a shootout started, so its kicks come from here.
    ///   - finalScore: the game's score. A running score that doesn't add up to it on
    ///     a finished match is dropped rather than shown wrong.
    ///   - isFinished: the match is over, so the FT/AET divider closes the timeline.
    ///   - currentPeriod: the period a live match is in, so a divider shows before the
    ///     period has an event of its own.
    public static func rows(
        events: [SoccerMatchEvent],
        shootoutDetails: [MatchIncident] = [],
        finalScore: SoccerScore?,
        isFinished: Bool,
        currentPeriod: Int? = nil
    ) -> [SoccerTimelineRow] {
        let inPlay = events.filter { ($0.period ?? 1) < 5 }
        let kicks = shootoutKicks(events: events.filter { $0.period == 5 }, details: shootoutDetails)
        let inShootout = !kicks.isEmpty || currentPeriod == 5

        // Running score, dropped if a finished match's goals don't add up.
        var running = SoccerScore(home: 0, away: 0)
        var scoreAfter: [String: SoccerScore] = [:]
        for event in inPlay where isGoal(event.type) {
            guard let side = event.side else { continue }
            running[side == .home ? .home : .away] += 1
            scoreAfter[event.id] = running
        }
        let scoresAddUp = !isFinished || finalScore == nil || running == finalScore
        if !scoresAddUp { scoreAfter = [:] }

        var rows: [SoccerTimelineRow] = []
        var period = 1
        var scoreSoFar: SoccerScore? = scoresAddUp ? SoccerScore(home: 0, away: 0) : nil
        for event in inPlay {
            let eventPeriod = max(event.period ?? period, period)
            while period < eventPeriod {
                rows.append(.divider(label: dividerLabel(after: period), score: scoreSoFar))
                period += 1
            }
            let after = scoreAfter[event.id]
            if let after { scoreSoFar = after }
            rows.append(.event(event, score: after))
        }
        // A live match past a break with nothing in the new period yet, or a finished
        // one whose second half had no events.
        let floor = (isFinished || inShootout) ? 2 : 1
        let reached = min(max(currentPeriod ?? period, period, floor), 4)
        while period < reached {
            rows.append(.divider(label: dividerLabel(after: period), score: scoreSoFar))
            period += 1
        }
        if isFinished || inShootout {
            rows.append(.divider(label: period <= 2 ? "FT" : "AET", score: finalScore ?? scoreSoFar))
        }
        if inShootout {
            rows.append(.shootoutHeader(score: kicks.isEmpty ? nil : tally(kicks).last))
            for (kick, tally) in zip(kicks, tally(kicks)) {
                rows.append(.shootoutKick(kick, tally: tally))
            }
        }
        return rows
    }

    static func isGoal(_ type: SoccerMatchEventType) -> Bool {
        type == .goal || type == .penaltyGoal || type == .ownGoal
    }

    private static func dividerLabel(after period: Int) -> String {
        switch period {
        case 1: return "HT"
        case 2: return "90'"
        case 3: return "ET HT"
        default: return "AET"
        }
    }

    private static func shootoutKicks(events: [SoccerMatchEvent], details: [MatchIncident]) -> [SoccerShootoutKick] {
        let fromEvents = events.compactMap { event -> SoccerShootoutKick? in
            guard let side = event.side else { return nil }
            let scored = event.type == .penaltyGoal || event.type == .goal
            guard scored || event.type == .penaltyMissed else { return nil }
            return SoccerShootoutKick(id: event.id, side: side == .home ? .home : .away,
                                      player: event.playerNames.first, scored: scored)
        }
        if !fromEvents.isEmpty { return fromEvents }
        return details.enumerated().compactMap { index, incident in
            guard let side = incident.side,
                  incident.kind == .shootoutGoal || incident.kind == .shootoutMiss else { return nil }
            return SoccerShootoutKick(id: "\(index)-\(incident.athlete ?? "")", side: side,
                                      player: incident.athlete, scored: incident.kind == .shootoutGoal)
        }
    }

    private static func tally(_ kicks: [SoccerShootoutKick]) -> [SoccerScore] {
        var score = SoccerScore(home: 0, away: 0)
        return kicks.map { kick in
            if kick.scored { score[kick.side] += 1 }
            return score
        }
    }
}

// MARK: - Live Activity

/// A soccer Live Activity's extras: red cards and the latest goal. Built the same
/// way by the server's APNS push and the app's foreground update, so the two agree.
public struct LiveActivitySoccer: Codable, Hashable, Sendable {
    /// Nil for none, to keep the push small.
    public var homeRedCards: Int?
    public var awayRedCards: Int?
    /// "Saka 67'", "van Dijk 80' (OG)".
    public var lastGoal: String?

    public init(homeRedCards: Int? = nil, awayRedCards: Int? = nil, lastGoal: String? = nil) {
        self.homeRedCards = homeRedCards
        self.awayRedCards = awayRedCards
        self.lastGoal = lastGoal
    }

    /// Nil for other sports, or a match with no goal or red card yet.
    public init?(game: Game) {
        guard game.sportType == .soccer, let details = game.soccerDetails, !details.isEmpty else { return nil }
        let home = game.redCards(.home), away = game.redCards(.away)
        var lastGoal: String?
        if let goal = details.last(where: { $0.kind == .goal || $0.kind == .penaltyGoal || $0.kind == .ownGoal }) {
            let note = goal.kind == .penaltyGoal ? " (P)" : goal.kind == .ownGoal ? " (OG)" : ""
            let name = Game.rowName(goal.athlete) ?? "Goal"
            lastGoal = [name, goal.clock].compactMap { $0 }.joined(separator: " ") + note
        }
        guard home + away > 0 || lastGoal != nil else { return nil }
        self.init(homeRedCards: home > 0 ? home : nil, awayRedCards: away > 0 ? away : nil, lastGoal: lastGoal)
    }
}
