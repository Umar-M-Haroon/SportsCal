//
//  ESPNCricketBoard.swift
//  SportsCalModel
//
//  ESPN's cricket boards. Both the all-cricket score panel
//  (`/sports/cricket/scorepanel[?dates=YYYYMMDD]`, a `scores` array of one competition
//  each) and a league scoreboard (`/sports/cricket/{leagueId}/scoreboard`, the same
//  competition shape at the top level) decode through `ESPNCricketBoard`.
//
//  Cricket's numbers come back in mixed types: `internationalClassId` is a string,
//  `winner` is "true"/"false" on the panel but a Bool on the summary, `isCurrent` is 0/1.
//

import Foundation

public struct ESPNCricketBoard: Decodable {
    public struct Competition: Decodable {
        public var leagues: [League]?
        public var events: [Event]?
    }

    public struct League: Decodable {
        public var id: String?
        public var name: String?
        /// Match days, on a league scoreboard.
        public var calendar: [String]?
    }

    public struct Event: Decodable {
        public var id: String
        public var date: String?
        public var endDate: String?
        public var name: String?
        public var competitions: [Match]?
    }

    public struct Match: Decodable {
        public var description: String?
        public var `class`: MatchClass?
        public var venue: Venue?
        public var status: Status?
        public var competitors: [Side]?
        public var timeValid: Bool?
    }

    public struct MatchClass: Decodable {
        public var internationalClassId: ESPNFlexibleNumber?
        public var eventType: String?
    }

    public struct Venue: Decodable {
        public var fullName: String?
    }

    public struct Status: Decodable {
        public struct Kind: Decodable {
            public var description: String?
            public var shortDetail: String?
            /// "pre", "in", "post".
            public var state: String?
        }
        public var session: String?
        public var summary: String?
        public var type: Kind?
    }

    public struct Side: Decodable {
        public var homeAway: String?
        public var score: String?
        public var winner: LenientBool?
        public var team: Team?
        public var linescores: [Innings]?
    }

    public struct Team: Decodable {
        public var id: String?
        public var displayName: String?
        public var abbreviation: String?
        public var logo: String?
        public var color: String?
    }

    public struct Innings: Decodable {
        public var period: Int?
        public var runs: Int?
        public var wickets: Int?
        public var overs: Double?
        public var isBatting: Bool?
        public var description: String?
        public var isCurrent: LenientBool?
    }

    /// `true`, `"true"` or `1`.
    public struct LenientBool: Decodable {
        public var value: Bool?
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let bool = try? container.decode(Bool.self) {
                value = bool
            } else if let text = try? container.decode(String.self) {
                value = text.lowercased() == "true" || text == "1"
            } else if let number = try? container.decode(Int.self) {
                value = number != 0
            }
        }
    }

    /// Score panel: one competition per entry.
    public var scores: [Competition]?
    /// League scoreboard: one competition at the top level.
    public var leagues: [League]?
    public var events: [Event]?

    public var competitions: [Competition] {
        if let scores { return scores }
        return [Competition(leagues: leagues, events: events)]
    }

    /// Every match we carry, as games. Competitions we don't carry are dropped
    /// (`CricketCompetition.league`).
    public func games() -> [Game] {
        competitions.flatMap { competition -> [Game] in
            let league = competition.leagues?.first
            return (competition.events ?? []).compactMap {
                Self.game(from: $0, espnLeagueID: league?.id.flatMap(Int.init), leagueName: league?.name)
            }
        }
    }

    static func game(from event: Event, espnLeagueID: Int?, leagueName: String?) -> Game? {
        guard let match = event.competitions?.first,
              let home = match.competitors?.first(where: { $0.homeAway == "home" }),
              let away = match.competitors?.first(where: { $0.homeAway == "away" }),
              let homeTeam = home.team, let awayTeam = away.team,
              let homeID = homeTeam.id, let awayID = awayTeam.id else { return nil }
        let homeName = homeTeam.displayName ?? ""
        let awayName = awayTeam.displayName ?? ""
        let classID = match.class?.internationalClassId?.value.map { Int($0) }
        guard let league = CricketCompetition.league(
            espnLeagueID: espnLeagueID, leagueName: leagueName,
            internationalClassID: classID, teamNames: [homeName, awayName]
        ) else { return nil }

        let format = CricketFormat(internationalClassID: classID, eventType: match.class?.eventType, leagueName: leagueName)
        let state = match.status?.type?.state
        let description = match.status?.type?.description
        let summary = match.status?.summary?.nilIfBlank
        let innings = Self.innings(home: home, away: away, live: state == "in")
        let scoreTexts = [home.score, away.score].compactMap { $0 }
        let extras = CricketMatchExtras(
            format: format,
            innings: innings,
            summary: summary,
            session: match.status?.session?.nilIfBlank,
            statusDetail: description,
            target: scoreTexts.lazy.compactMap(CricketScoreText.target(in:)).first,
            scheduledOvers: scoreTexts.lazy.compactMap(CricketScoreText.scheduledOvers(in:)).first ?? format.defaultOvers,
            matchLabel: match.description?.nilIfBlank,
            seriesName: leagueName,
            isAbandoned: description.map { ["Abandoned", "No result", "Cancelled"].contains($0) } == true ? true : nil,
            isDraw: (description == "Draw" || summary?.localizedCaseInsensitiveContains("drawn") == true) ? true : nil
        )
        let homeWinner = home.winner?.value
        let awayWinner = away.winner?.value
        let started = state != "pre"
        return Game(
            idLiveScore: event.id, idEvent: event.id, strSport: SportType.cricket.rawValue,
            idLeague: "\(league.rawValue)",
            idHomeTeam: league.teamID(espnID: homeID), idAwayTeam: league.teamID(espnID: awayID),
            strHomeTeam: homeName, strAwayTeam: awayName,
            strHomeTeamBadge: homeTeam.logo?.nilIfBlank, strAwayTeamBadge: awayTeam.logo?.nilIfBlank,
            intHomeScore: started ? home.score?.nilIfBlank : nil,
            intAwayScore: started ? away.score?.nilIfBlank : nil,
            strStatus: state,
            strProgress: state == "pre" ? nil : (description ?? match.status?.type?.shortDetail),
            strTimestamp: event.date,
            lastPlay: state == "pre" ? nil : summary,
            isCompleted: state == "post",
            isoDate: event.date.flatMap(DateParsers.parse),
            venueName: match.venue?.fullName,
            homeTeamColor: homeTeam.color?.nilIfBlank, awayTeamColor: awayTeam.color?.nilIfBlank,
            tournamentName: leagueName,
            round: match.description?.nilIfBlank,
            // ESPN gives every match an end date, but for a one-day game it's just "the
            // day after"; only Tests and first-class games really run to it.
            endDate: format.isMultiDay ? event.endDate : nil,
            scoreboardExtras: ScoreboardExtras(
                homeWinner: homeWinner == true ? true : (state == "post" && awayWinner == true ? false : nil),
                awayWinner: awayWinner == true ? true : (state == "post" && homeWinner == true ? false : nil),
                cricket: extras
            ),
            homeAbbreviation: homeTeam.abbreviation,
            awayAbbreviation: awayTeam.abbreviation,
            timeTBD: match.timeValid == false && state == "pre"
        )
    }

    /// Each side's innings in match order. ESPN lists every innings period on both
    /// sides; only the batting side's entry carries runs.
    /// `live`: ESPN keeps flagging the last innings as current after the match ends.
    static func innings(home: Side, away: Side, live: Bool) -> [CricketInnings] {
        func build(_ side: Side, _ which: GameSituation.Side) -> [CricketInnings] {
            let segments = (side.score ?? "").components(separatedBy: " & ")
            return (side.linescores ?? [])
                .filter { $0.isBatting == true }
                .sorted { ($0.period ?? 0) < ($1.period ?? 0) }
                .enumerated()
                .map { index, line in
                    let segment = index < segments.count ? segments[index] : ""
                    return CricketInnings(
                        side: which,
                        number: line.period ?? index + 1,
                        runs: line.runs ?? 0,
                        wickets: line.wickets ?? 0,
                        overs: line.overs,
                        declared: CricketScoreText.isDeclared(segment) || line.description == "declared",
                        isCurrent: live && line.isCurrent?.value == true
                    )
                }
        }
        return (build(home, .home) + build(away, .away)).sorted { $0.number < $1.number }
    }
}

// MARK: - Score text

/// Reads the bits of ESPN's score text ("184 (40.5/50 ov, target 246)", "392/9d") that
/// aren't in the innings linescores.
public enum CricketScoreText {
    public static func target(in text: String) -> Int? {
        guard let range = text.range(of: "target ") else { return nil }
        return Int(text[range.upperBound...].prefix(while: \.isNumber))
    }

    /// The 50 in "(40.5/50 ov".
    public static func scheduledOvers(in text: String) -> Int? {
        guard let ov = text.range(of: " ov") else { return nil }
        let head = text[..<ov.lowerBound]
        guard let slash = head.lastIndex(of: "/"), head[..<slash].last?.isNumber == true else { return nil }
        let digits = head[head.index(after: slash)...]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }

    /// "392/9d".
    public static func isDeclared(_ segment: String) -> Bool {
        let score = segment.split(separator: " ").first ?? ""
        return score.hasSuffix("d") && score.dropLast().allSatisfy { $0.isNumber || $0 == "/" }
    }
}

extension CricketFormat {
    /// Overs per side when ESPN's score text doesn't say.
    var defaultOvers: Int? {
        switch self {
        case .odi, .listA: 50
        case .t20: 20
        case .t10: 10
        case .test, .firstClass, .hundred, .other: nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespaces).isEmpty ? nil : self
    }
}
