//
//  FantasyStatLines.swift
//  SportsCalModel
//
//  Every player's fantasy-relevant numbers for one game, built from the ESPN summary
//  the server already fetches for play-by-play. On top of the box score
//  (`PlayerLiveStatLine`) it adds what fantasy scoring needs and the box leaves out:
//  football field goals by distance, two-point conversions (both read from the
//  scoring plays) and a D/ST line per team.
//

import Foundation

/// One player's line for one game, as `/fantasy` serves it.
public struct FantasyPlayerLine: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// ESPN athlete ID; `dst-{teamID}` for a team defense.
    public var athleteID: String
    /// "Jahmyr Gibbs", "Lions D/ST".
    public var name: String
    /// "J. Gibbs".
    public var shortName: String?
    /// "QB", "RB", "WR", "TE", "K", "DST". Nil when no roster had the player.
    public var position: String?
    public var jersey: String?
    public var headshot: String?
    /// ESPN team ID.
    public var teamID: String
    public var teamAbbreviation: String?
    public var opponentAbbreviation: String?
    public var isHome: Bool?
    /// ESPN event ID.
    public var eventID: String
    /// The TheSportsDB event the app knows this game by, where there is one.
    public var tsdbEventID: String?
    /// Stat key → value (`FantasyStatKey`, `PlayerLiveStatLine` keys).
    public var stats: [String: Double]
    /// ESPN's "pre" / "in" / "post".
    public var gameState: String?
    /// 0…1 through regulation; 1 once final.
    public var gameProgress: Double?
    /// "Q3 4:12", "Final", "Final/OT".
    public var gameStatus: String?
    /// The game's start, for ordering and "Thu" labels.
    public var gameDate: Date?
    /// Per-game average of `stats` over the season's other finished games.
    public var seasonAverage: [String: Double]?
    public var seasonGames: Int?

    public var id: String { athleteID + "|" + eventID }

    /// ESPN's headshot for an athlete (the box score's own URL, which the wire leaves out).
    public static func standardHeadshot(athleteID: String, sport: SportType) -> String? {
        switch sport {
        case .nfl: return "https://a.espncdn.com/i/headshots/nfl/players/full/\(athleteID).png"
        default: return nil
        }
    }

    /// The headshot to show: the line's own (D/ST team logos), else ESPN's standard one.
    public func headshotURL(sport: SportType) -> URL? {
        (headshot ?? (isDST ? nil : Self.standardHeadshot(athleteID: athleteID, sport: sport))).flatMap(URL.init(string:))
    }
    public var isDST: Bool { athleteID.hasPrefix(FantasyStatLines.dstPrefix) }
    public var isFinal: Bool { gameState == "post" }
    public var isLive: Bool { gameState == "in" }

    public init(
        athleteID: String, name: String, shortName: String? = nil, position: String? = nil,
        jersey: String? = nil, headshot: String? = nil, teamID: String, teamAbbreviation: String? = nil,
        opponentAbbreviation: String? = nil, isHome: Bool? = nil, eventID: String, tsdbEventID: String? = nil,
        stats: [String: Double], gameState: String? = nil, gameProgress: Double? = nil,
        gameStatus: String? = nil, gameDate: Date? = nil,
        seasonAverage: [String: Double]? = nil, seasonGames: Int? = nil
    ) {
        self.athleteID = athleteID
        self.name = name
        self.shortName = shortName
        self.position = position
        self.jersey = jersey
        self.headshot = headshot
        self.teamID = teamID
        self.teamAbbreviation = teamAbbreviation
        self.opponentAbbreviation = opponentAbbreviation
        self.isHome = isHome
        self.eventID = eventID
        self.tsdbEventID = tsdbEventID
        self.stats = stats
        self.gameState = gameState
        self.gameProgress = gameProgress
        self.gameStatus = gameStatus
        self.gameDate = gameDate
        self.seasonAverage = seasonAverage
        self.seasonGames = seasonGames
    }
}

public enum FantasyStatLines {
    public static let dstPrefix = "dst-"

    public static func dstAthleteID(teamID: String) -> String { dstPrefix + teamID }

    /// Every player line in `summary` (plus a D/ST line per team for football), with
    /// the game context left for the caller to fill. Empty for sports fantasy doesn't
    /// score yet.
    public static func lines(summary: ESPNSummaryResponse, sport: SportType, eventID: String) -> [FantasyPlayerLine] {
        guard FantasyScoring.supports(sport) else { return [] }
        let base = PlayerLiveStatLine.lines(boxscore: summary.boxscore, sport: sport)
        guard !base.isEmpty else { return [] }

        // Team context from the team-stats block: side and abbreviation.
        var sides: [String: String] = [:]
        var abbreviations: [String: String] = [:]
        for team in summary.boxscore?.teams ?? [] {
            guard let id = team.team?.id else { continue }
            if let side = team.homeAway { sides[id] = side }
            if let abbr = team.team?.abbreviation { abbreviations[id] = abbr }
        }
        for team in summary.boxscore?.players ?? [] {
            if let id = team.team?.id, let abbr = team.team?.abbreviation { abbreviations[id] = abbreviations[id] ?? abbr }
        }
        let teamIDs = Array(Set(base.map(\.teamID))).sorted()
        func opponent(of teamID: String) -> String? { teamIDs.first { $0 != teamID } }

        let athletes = athleteDetails(summary.boxscore)
        var lines: [FantasyPlayerLine] = base.map { line in
            let details = athletes[line.athleteID]
            let opponentID = opponent(of: line.teamID)
            return FantasyPlayerLine(
                athleteID: line.athleteID,
                name: line.name,
                shortName: details?.shortName,
                position: details?.position,
                jersey: details?.jersey,
                headshot: details?.headshot,
                teamID: line.teamID,
                teamAbbreviation: abbreviations[line.teamID],
                opponentAbbreviation: opponentID.flatMap { abbreviations[$0] },
                isHome: sides[line.teamID].map { $0 == "home" },
                eventID: eventID,
                stats: line.stats
            )
        }

        if sport == .nfl {
            let plays = summary.scoringPlays ?? []
            applyScoringPlays(plays, to: &lines)
            // The D/ST lines read defensive columns the trim below drops.
            let defenses = dstLines(from: lines, plays: plays, teamIDs: teamIDs, sides: sides,
                                    abbreviations: abbreviations, eventID: eventID)
            lines = trimmed(lines, sport: sport) + defenses
        }
        return lines
    }

    /// The stats fantasy reads (scoring and the stat summary). Everything else — QBR,
    /// long gains, per-attempt averages, tacklers — is dropped, and so are players left
    /// with nothing: a week of lines goes from ~700KB to a fraction of it.
    public static func fantasyKeys(for sport: SportType) -> Set<String> {
        typealias K = FantasyStatKey.NFL
        switch sport {
        case .nfl:
            return Set(FantasyStatKey.editable(for: .nfl)).union([
                K.fieldGoalsMade, K.fieldGoalAttempts, K.extraPointAttempts, K.fumbles,
            ])
        default:
            return []
        }
    }

    static func trimmed(_ lines: [FantasyPlayerLine], sport: SportType) -> [FantasyPlayerLine] {
        let keys = fantasyKeys(for: sport)
        return lines.compactMap { line in
            var line = line
            line.stats = line.stats.filter { keys.contains($0.key) && $0.value != 0 }
            // A box-score headshot is ESPN's standard URL; the app rebuilds it from the ID.
            if line.headshot == FantasyPlayerLine.standardHeadshot(athleteID: line.athleteID, sport: sport) {
                line.headshot = nil
            }
            return line.stats.isEmpty ? nil : line
        }
    }

    // MARK: Athlete details

    struct AthleteDetails {
        var shortName: String?
        var position: String?
        var jersey: String?
        var headshot: String?
    }

    static func athleteDetails(_ boxscore: ESPNSummaryBoxscore?) -> [String: AthleteDetails] {
        var out: [String: AthleteDetails] = [:]
        for team in boxscore?.players ?? [] {
            for group in team.statistics ?? [] {
                for line in group.athletes ?? [] {
                    guard let athlete = line.athlete, let id = athlete.id else { continue }
                    var details = out[id] ?? AthleteDetails()
                    details.shortName = details.shortName ?? athlete.shortName ?? athlete.displayName.map(PlayerBoxScore.shortName(from:))
                    details.position = details.position ?? athlete.position?.abbreviation ?? line.position?.abbreviation
                    details.jersey = details.jersey ?? athlete.jersey
                    details.headshot = details.headshot ?? athlete.headshot?.href
                    out[id] = details
                }
            }
        }
        return out
    }

    // MARK: Scoring plays (football)

    /// Adds field goals by distance and two-point conversions, read from the scoring
    /// plays' text: "Jake Bates 44 Yd Field Goal", "(Caleb Williams Run for Two-Point
    /// Conversion)", "(Jared Goff Pass to Amon-Ra St. Brown for Two-Point Conversion)".
    static func applyScoringPlays(_ plays: [ESPNSummaryResponse.ScoringPlay], to lines: inout [FantasyPlayerLine]) {
        typealias K = FantasyStatKey.NFL
        func add(_ key: String, name: String, teamID: String?) {
            guard let index = lineIndex(named: name, teamID: teamID, in: lines) else { return }
            lines[index].stats[key, default: 0] += 1
        }
        for play in plays {
            guard let text = play.text else { continue }
            let teamID = play.team?.id
            if let goal = fieldGoal(in: text) {
                let key = goal.yards >= 50 ? K.fieldGoals50plus : goal.yards >= 40 ? K.fieldGoals40to49 : K.fieldGoals0to39
                add(key, name: goal.kicker, teamID: teamID)
            }
            for name in twoPointScorers(in: text) {
                add(K.twoPointConversions, name: name, teamID: teamID)
            }
        }
    }

    /// "Jake Bates 44 Yd Field Goal" → ("Jake Bates", 44).
    static func fieldGoal(in text: String) -> (kicker: String, yards: Int)? {
        guard let range = text.range(of: " Yd Field Goal", options: .caseInsensitive) else { return nil }
        let before = text[..<range.lowerBound]
        guard let space = before.lastIndex(of: " "), let yards = Int(before[before.index(after: space)...]) else { return nil }
        let kicker = before[..<space].trimmingCharacters(in: .whitespaces)
        return kicker.isEmpty ? nil : (kicker, yards)
    }

    /// The players credited with a successful two-point try: the runner; or the
    /// passer and the receiver.
    static func twoPointScorers(in text: String) -> [String] {
        guard let open = text.lastIndex(of: "("), let close = text.lastIndex(of: ")"), open < close else { return [] }
        let inner = String(text[text.index(after: open)..<close])
        let lower = inner.lowercased()
        guard lower.contains("two-point") || lower.contains("2pt") || lower.contains("2-pt"),
              !lower.contains("fail"), !lower.contains("no good") else { return [] }
        if let pass = inner.range(of: " Pass to ", options: .caseInsensitive) {
            let passer = String(inner[..<pass.lowerBound])
            let rest = inner[pass.upperBound...]
            let receiver = rest.range(of: " for ", options: .caseInsensitive).map { String(rest[..<$0.lowerBound]) } ?? String(rest)
            return [passer, receiver].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let run = inner.range(of: " Run for ", options: .caseInsensitive) {
            let runner = inner[..<run.lowerBound].trimmingCharacters(in: .whitespaces)
            return runner.isEmpty ? [] : [runner]
        }
        return []
    }

    /// The line for a player named in play text: full name on the scoring team first,
    /// then anyone in the game.
    static func lineIndex(named name: String, teamID: String?, in lines: [FantasyPlayerLine]) -> Int? {
        let wanted = normalized(name)
        let matches = lines.indices.filter { normalized(lines[$0].name) == wanted }
        if let teamID, let onTeam = matches.first(where: { lines[$0].teamID == teamID }) { return onTeam }
        return matches.first
    }

    /// Case, accents, punctuation and suffixes don't decide a match ("Amon-Ra St. Brown").
    public static func normalized(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !["jr", "sr", "ii", "iii", "iv", "v"].contains($0) }
        return words.joined()
    }

    // MARK: D/ST (football)

    static func dstLines(
        from lines: [FantasyPlayerLine],
        plays: [ESPNSummaryResponse.ScoringPlay],
        teamIDs: [String],
        sides: [String: String],
        abbreviations: [String: String],
        eventID: String
    ) -> [FantasyPlayerLine] {
        typealias K = FantasyStatKey.NFL
        guard teamIDs.count == 2 else { return [] }
        let last = plays.last
        func total(_ key: String, team: String) -> Double {
            lines.filter { $0.teamID == team }.reduce(0) { $0 + ($1.stats[key] ?? 0) }
        }
        return teamIDs.map { teamID in
            let opponentID = teamIDs.first { $0 != teamID }!
            var stats: [String: Double] = [:]
            stats[K.dstSacks] = total(K.sacksTaken, team: opponentID)
            stats[K.dstInterceptions] = total(K.interceptionsThrown, team: opponentID)
            stats[K.dstFumblesRecovered] = total(K.fumblesLost, team: opponentID)
            stats[K.dstTouchdowns] = total("defensive.defensiveTouchdowns", team: teamID)
                + total(K.kickReturnTouchdowns, team: teamID) + total(K.puntReturnTouchdowns, team: teamID)
            stats[K.dstSafeties] = Double(plays.filter { play in
                play.team?.id == teamID && (play.type?.abbreviation == "SF" || play.text?.localizedCaseInsensitiveContains("safety") == true)
            }.count)
            let opponentSide = sides[opponentID]
            let allowed = opponentSide == "home" ? last?.homeScore : opponentSide == "away" ? last?.awayScore : nil
            stats[K.dstPointsAllowed] = Double(allowed ?? 0)
            let abbr = abbreviations[teamID]
            return FantasyPlayerLine(
                athleteID: dstAthleteID(teamID: teamID),
                name: "\(abbr ?? "Team") D/ST",
                shortName: "\(abbr ?? "Team") D/ST",
                position: "DST",
                headshot: abbr.map { "https://a.espncdn.com/i/teamlogos/nfl/500/\($0.lowercased()).png" },
                teamID: teamID,
                teamAbbreviation: abbr,
                opponentAbbreviation: abbreviations[opponentID],
                isHome: sides[teamID].map { $0 == "home" },
                eventID: eventID,
                stats: stats
            )
        }
    }
}

// MARK: - Game context

public extension FantasyStatLines {
    struct GameContext: Equatable, Sendable {
        public var state: String?
        public var status: String?
        public var progress: Double?
        public var date: Date?
        public var season: Int?
        public var seasonType: Int?
        public var week: Int?
    }

    /// The game's state and how far along it is, from the summary header.
    static func context(header: ESPNSummaryHeader?, sport: SportType) -> GameContext {
        let competition = header?.competition
        let state = competition?.status?.type?.state
        let progress: Double?
        switch state {
        case "post": progress = 1
        case "pre": progress = 0
        case "in":
            progress = competition?.status.flatMap { status in
                status.period.map { regulationProgress(sport: sport, period: $0, clock: status.clock ?? 0) }
            }
        default: progress = nil
        }
        return GameContext(
            state: state,
            status: competition?.status?.type?.shortDetail,
            progress: progress,
            date: competition?.date.flatMap(DateParsers.parse),
            season: header?.season?.year,
            seasonType: header?.season?.type,
            week: header?.week
        )
    }

    /// 0…1 through regulation. Football: four 15-minute quarters; overtime counts as done.
    static func regulationProgress(sport: SportType, period: Int, clock: Double) -> Double {
        switch sport {
        case .nfl:
            guard period >= 1 else { return 0 }
            guard period <= 4 else { return 1 }
            let quarter = 15.0 * 60
            let elapsed = Double(period - 1) * quarter + (quarter - min(max(clock, 0), quarter))
            return min(max(elapsed / (4 * quarter), 0), 1)
        default:
            return 0
        }
    }

    /// `lines` with the game context filled in.
    static func applying(_ context: GameContext, tsdbEventID: String?, to lines: [FantasyPlayerLine]) -> [FantasyPlayerLine] {
        lines.map { line in
            var line = line
            line.gameState = context.state
            line.gameStatus = context.status
            line.gameProgress = context.progress
            line.gameDate = context.date
            line.tsdbEventID = tsdbEventID ?? line.tsdbEventID
            return line
        }
    }
}
