//
//  GameSituation+HoopsHockey.swift
//  SportsCalModel
//
//  The basketball and hockey slices of a live situation: team fouls, the bonus, the
//  ball and scoring runs; skaters, power plays and pulled goalies.
//
//  Neither comes from ESPN's scoreboard situation, which for these sports carries only
//  the last play. Basketball fouls, timeouts and runs are counted from the play-by-play
//  the server already fetches each minute (`BasketballPlayTally`); hockey strength comes
//  from the NHL's own feed (`applyNHLSituationCode`). Both are partial sources, so an
//  ESPN tick that replaces the situation whole must carry them over
//  (`carryingSupplementalState`) rather than wipe them every five seconds.
//

import Foundation

// MARK: - Derived

public extension GameSituation {
    var hasBasketballState: Bool {
        homeFouls != nil || awayFouls != nil || ballSide != nil || runSide != nil
    }

    /// Whether there's basketball or hockey state worth a line: fouls, the ball or a run;
    /// a power play or a pulled goalie (even strength alone says nothing).
    var hasHoopsHockeyDisplay: Bool {
        hasBasketballState || powerPlaySide != nil || emptyNetSide != nil
    }

    /// Whether the skater strength is known. Even strength counts: it's what clears a
    /// power play.
    var hasHockeyState: Bool { homeSkaters != nil && awaySkaters != nil }

    /// The side on the power play: more skaters, not counting the extra attacker a
    /// pulled goalie sends out. Nil at even strength (3-on-3 overtime included).
    var powerPlaySide: Side? {
        guard let home = homeSkaters, let away = awaySkaters else { return nil }
        let homeSkating = home - (homeGoaliePulled == true ? 1 : 0)
        let awaySkating = away - (awayGoaliePulled == true ? 1 : 0)
        if homeSkating > awaySkating { return .home }
        if awaySkating > homeSkating { return .away }
        return nil
    }

    /// The side whose net is empty (goalie pulled).
    var emptyNetSide: Side? {
        if homeGoaliePulled == true { return .home }
        if awayGoaliePulled == true { return .away }
        return nil
    }

    /// "5-on-4", while the sides are uneven.
    var strengthText: String? {
        guard let home = homeSkaters, let away = awaySkaters, home != away else { return nil }
        return "\(max(home, away))-on-\(min(home, away))"
    }

    /// "1:42" left on the power play.
    var powerPlayClockText: String? {
        guard powerPlaySide != nil, let clock = powerPlayClock, clock > 0 else { return nil }
        let seconds = Int(clock.rounded())
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    /// Fouls `side`'s opponent has committed this period, which is what puts `side` in the bonus.
    func opponentFouls(of side: Side) -> Int? {
        side == .home ? awayFouls : homeFouls
    }

    /// Whether `side` shoots free throws on every foul now: its opponent is at the
    /// league's team-foul limit for the period. Nil when the fouls or the rule are unknown.
    func isInBonus(_ side: Side, league: Leagues?) -> Bool? {
        guard let fouls = opponentFouls(of: side),
              let limit = league?.bonusFoulLimit(period: period ?? 1) else { return nil }
        return fouls >= limit
    }

    /// College's double bonus (two shots on every foul), at ten fouls in a half.
    func isInDoubleBonus(_ side: Side, league: Leagues?) -> Bool {
        guard league == .ncaaMBBTournament, let fouls = opponentFouls(of: side) else { return false }
        return fouls >= 10
    }
}

public extension Leagues {
    /// The team foul in a period that first sends the other side to the line: the 5th
    /// in an NBA or WNBA quarter (the 4th in overtime), the 7th in a college half (the
    /// 1-and-1). Nil outside basketball.
    func bonusFoulLimit(period: Int) -> Int? {
        switch self {
        case .nba, .wnba: return period > (regulationPeriods ?? 4) ? 4 : 5
        case .ncaaMBBTournament: return 7
        default: return nil
        }
    }
}

// MARK: - Basketball: the ball

extension GameSituation {
    /// Who has the ball after a play by `side`, where the play says so: a rebound is the
    /// rebounder's ball; a made basket, a last made free throw or a turnover is the other
    /// side's. Fouls, timeouts and missed shots don't say (the rebound will).
    static func basketballBallSide(afterPlay type: String, scoreValue: Int, by side: Side) -> Side? {
        let text = type.lowercased()
        if text.contains("rebound") { return side }
        if text.contains("turnover") { return side.opposite }
        if text.contains("free throw") {
            // "Free Throw - 2 of 2": only the last one hands the ball over, and only if made.
            guard scoreValue > 0, let range = text.range(of: #"(\d+) of (\d+)"#, options: .regularExpression) else { return nil }
            let numbers = text[range].split(separator: " ").compactMap { Int($0) }
            return numbers.count == 2 && numbers[0] == numbers[1] ? side.opposite : nil
        }
        if scoreValue > 0 { return side.opposite }
        return nil
    }
}

// MARK: - Hockey: the NHL situation code

public extension GameSituation {
    /// Applies the NHL's four-digit situation code: away goalie, away skaters, home
    /// skaters, home goalie. "1551" is even strength, "1451" a home power play, "0651"
    /// the away side with its goalie pulled. False (and nothing changed) for any other shape.
    @discardableResult
    mutating func applyNHLSituationCode(_ code: String) -> Bool {
        let digits = code.compactMap(\.wholeNumberValue)
        guard code.count == 4, digits.count == 4 else { return false }
        awayGoaliePulled = digits[0] == 0
        awaySkaters = digits[1]
        homeSkaters = digits[2]
        homeGoaliePulled = digits[3] == 0
        return true
    }

    /// Even strength with both goalies in: what an intermission or a feed without
    /// special teams means.
    mutating func setEvenStrength(skaters: Int = 5) {
        homeSkaters = skaters
        awaySkaters = skaters
        homeGoaliePulled = false
        awayGoaliePulled = false
        powerPlayClock = nil
    }
}

// MARK: - Merging

public extension GameSituation {
    /// Takes the basketball and hockey state from a partial source's `fresh` copy (see
    /// `overlaying`). Hockey strength travels as a group: a fresh "even strength" must
    /// clear the old power play, its clock and a pulled goalie together.
    mutating func takeHoopsHockeyState(from fresh: GameSituation) {
        if fresh.hasHockeyState {
            homeSkaters = fresh.homeSkaters
            awaySkaters = fresh.awaySkaters
            homeGoaliePulled = fresh.homeGoaliePulled
            awayGoaliePulled = fresh.awayGoaliePulled
            powerPlayClock = fresh.powerPlayClock
        }
        homeFouls = fresh.homeFouls ?? homeFouls
        awayFouls = fresh.awayFouls ?? awayFouls
        ballSide = fresh.ballSide ?? ballSide
        if fresh.runSide != nil {
            runSide = fresh.runSide
            runPoints = fresh.runPoints
        }
    }

    /// This situation (ESPN's, which never carries them) with the state partial sources
    /// add carried over from `old`, while it still holds:
    ///
    /// - Basketball fouls, within the same period; timeouts, always.
    /// - A scoring run, while the other side hasn't scored since; points the running side
    ///   added since extend it.
    /// - Hockey strength, within the same period and at the same score (a power-play goal
    ///   ends a minor). The NHL feed re-sends it every few seconds anyway.
    ///
    /// Scores are home/away as of `old` and now.
    func carryingSupplementalState(
        from old: GameSituation?,
        sport: SportType?,
        oldScore: (home: Int, away: Int),
        newScore: (home: Int, away: Int)
    ) -> GameSituation {
        guard let old else { return self }
        var merged = self
        let samePeriod = old.period == nil || period == nil || old.period == period
        switch sport {
        case .basketball:
            if merged.homeFouls == nil, merged.awayFouls == nil, samePeriod {
                merged.homeFouls = old.homeFouls
                merged.awayFouls = old.awayFouls
            }
            if merged.homeTimeouts == nil, merged.awayTimeouts == nil {
                merged.homeTimeouts = old.homeTimeouts
                merged.awayTimeouts = old.awayTimeouts
            }
            if merged.runSide == nil, let side = old.runSide, let points = old.runPoints {
                let homeAdded = newScore.home - oldScore.home
                let awayAdded = newScore.away - oldScore.away
                let (ours, theirs) = side == .home ? (homeAdded, awayAdded) : (awayAdded, homeAdded)
                if theirs == 0, ours >= 0 {
                    merged.runSide = side
                    merged.runPoints = points + ours
                }
            }
        case .hockey:
            if !merged.hasHockeyState, old.hasHockeyState, samePeriod,
               oldScore.home == newScore.home, oldScore.away == newScore.away {
                merged.homeSkaters = old.homeSkaters
                merged.awaySkaters = old.awaySkaters
                merged.homeGoaliePulled = old.homeGoaliePulled
                merged.awayGoaliePulled = old.awayGoaliePulled
                merged.powerPlayClock = old.powerPlayClock
            }
        default:
            break
        }
        return merged
    }
}

// MARK: - Basketball: counted from the play-by-play

/// Team fouls, timeouts left and the current run, counted from a game's play-by-play.
/// ESPN's scoreboard has none of them; its core situation endpoint has fouls but would
/// cost a request per game per tick, and the server already holds the plays.
public struct BasketballPlayTally: Codable, Equatable, Hashable, Sendable {
    /// The period the fouls are for.
    public var period: Int
    public var homeFouls: Int
    public var awayFouls: Int
    /// Timeouts left. NBA only: the other leagues' allowances (media timeouts, carry-over)
    /// can't be told from the plays.
    public var homeTimeouts: Int?
    public var awayTimeouts: Int?
    public var runSide: GameSituation.Side?
    public var runPoints: Int?

    public init(period: Int, homeFouls: Int, awayFouls: Int, homeTimeouts: Int? = nil, awayTimeouts: Int? = nil,
                runSide: GameSituation.Side? = nil, runPoints: Int? = nil) {
        self.period = period
        self.homeFouls = homeFouls
        self.awayFouls = awayFouls
        self.homeTimeouts = homeTimeouts
        self.awayTimeouts = awayTimeouts
        self.runSide = runSide
        self.runPoints = runPoints
    }

    /// A run worth a chip: this many unanswered points.
    public static let minimumRun = 8

    /// Counts from `plays` (oldest first), with `teamIDs[i]` the ESPN team of `plays[i]`.
    /// Nil without plays or a period.
    public init?(plays: [Play], teamIDs: [String?], homeTeamID: String?, awayTeamID: String?, league: Leagues?) {
        guard let period = plays.last(where: { $0.period?.number != nil })?.period?.number else { return nil }
        func side(_ index: Int) -> GameSituation.Side? {
            guard index < teamIDs.count, let id = teamIDs[index] else { return nil }
            if id == homeTeamID { return .home }
            if id == awayTeamID { return .away }
            return nil
        }
        let regulation = league?.regulationPeriods ?? 4
        // College fouls run on from the second half through overtime; the pros reset
        // them every quarter and every overtime.
        let foulPeriods: ClosedRange<Int> = league == .ncaaMBBTournament && period >= 2 ? 2...max(2, period) : period...period

        var fouls: [GameSituation.Side: Int] = [.home: 0, .away: 0]
        var timeoutsInGame: [GameSituation.Side: Int] = [.home: 0, .away: 0]
        var timeoutsInPeriod: [GameSituation.Side: Int] = [.home: 0, .away: 0]
        for (index, play) in plays.enumerated() {
            guard let side = side(index), let type = play.type?.text?.lowercased(),
                  let number = play.period?.number else { continue }
            if foulPeriods.contains(number), Self.isTeamFoul(type) {
                fouls[side, default: 0] += 1
            }
            if Self.usesTimeout(type) {
                if number <= regulation { timeoutsInGame[side, default: 0] += 1 }
                if number == period { timeoutsInPeriod[side, default: 0] += 1 }
            }
        }
        self.period = period
        homeFouls = fouls[.home] ?? 0
        awayFouls = fouls[.away] ?? 0
        if league == .nba {
            func left(_ side: GameSituation.Side) -> Int {
                let usedInPeriod = timeoutsInPeriod[side] ?? 0
                // Seven a game, at most four of them in the 4th; two in each overtime.
                if period > regulation { return max(0, 2 - usedInPeriod) }
                let gameLeft = max(0, 7 - (timeoutsInGame[side] ?? 0))
                return period == regulation ? min(gameLeft, max(0, 4 - usedInPeriod)) : gameLeft
            }
            homeTimeouts = left(.home)
            awayTimeouts = left(.away)
        }
        if let run = Self.currentRun(plays), run.points >= Self.minimumRun {
            runSide = run.side
            runPoints = run.points
        }
    }

    /// ESPN's play types for a team foul, as its own team-foul count reads them (checked
    /// against its situation endpoint): personal, shooting, loose-ball, take, flagrant and
    /// offensive fouls; not technicals, and not the turnover logged beside an offensive foul.
    static func isTeamFoul(_ type: String) -> Bool {
        guard !type.contains("turnover"), !type.contains("technical") else { return false }
        return type.contains("foul") || type.contains("charge")
    }

    /// A team's timeout, or a lost coach's challenge (which costs one).
    static func usesTimeout(_ type: String) -> Bool {
        if type.contains("timeout") { return !type.contains("official") && !type.contains("tv") }
        return type.contains("challenge") && type.contains("stands")
    }

    /// The unanswered points at the end of `plays`: the side that scored last and how
    /// much it has scored since the other side last did.
    static func currentRun(_ plays: [Play]) -> (side: GameSituation.Side, points: Int)? {
        var states: [(home: Int, away: Int)] = []
        for play in plays {
            guard let home = play.homeScore, let away = play.awayScore else { continue }
            if let last = states.last, last.home == home, last.away == away { continue }
            states.append((home, away))
        }
        guard let end = states.last, states.count >= 2 else { return nil }
        let previous = states[states.count - 2]
        let side: GameSituation.Side
        if end.home > previous.home, end.away == previous.away { side = .home }
        else if end.away > previous.away, end.home == previous.home { side = .away }
        else { return nil }
        // Walk back while only `side` was scoring; the run starts where the other side last moved.
        var start = previous
        for state in states.dropLast().reversed() {
            let otherMoved = side == .home ? state.away != end.away : state.home != end.home
            if otherMoved { break }
            start = state
        }
        let points = side == .home ? end.home - start.home : end.away - start.away
        return points > 0 ? (side, points) : nil
    }

    /// Writes the counts onto a live situation. Fouls only land in the period they were
    /// counted for: a tally from the end of a quarter must not show at the start of the next.
    public func apply(to situation: inout GameSituation) {
        if situation.period == nil || situation.period == period {
            situation.homeFouls = homeFouls
            situation.awayFouls = awayFouls
        }
        if homeTimeouts != nil || awayTimeouts != nil {
            situation.homeTimeouts = homeTimeouts
            situation.awayTimeouts = awayTimeouts
        }
        situation.runSide = runSide
        situation.runPoints = runPoints
    }
}
