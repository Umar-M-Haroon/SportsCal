//
//  SoccerMatchBuilder.swift
//  SportsCalServer
//
//  Decodes the slice of ESPN's per-event soccer `summary` we use — team stats,
//  lineups, key events, commentary, recent form and head-to-head — and maps it
//  onto the shared `SoccerMatchDetail`, deriving shots (with estimated xG) and a
//  momentum series from the commentary's pitch coordinates.
//
//  Fetched on demand via `/soccer/match/:eventID` — see routes.swift.
//

import Foundation
import Vapor
import SportsCalModel

// MARK: - ESPN summary decode (only the fields we consume)

struct SoccerSummaryResponse: Codable {
    var header: SoccerSummaryHeader?
    var boxscore: SoccerBoxscore?
    var rosters: [SoccerRoster]?
    var keyEvents: [SoccerKeyEvent]?
    var commentary: [SoccerCommentary]?
    var lastFiveGames: [SoccerTeamGames]?
    /// Club fixtures carry head-to-head here…
    var seasonseries: [SoccerSeasonSeries]?
    /// …international fixtures here, shaped like `lastFiveGames`.
    var headToHeadGames: [SoccerTeamGames]?
}

struct SoccerSummaryHeader: Codable {
    var competitions: [SoccerHeaderCompetition]?
}

struct SoccerHeaderCompetition: Codable {
    var competitors: [SoccerHeaderCompetitor]?
    var status: SoccerHeaderStatus?
}

struct SoccerHeaderCompetitor: Codable {
    var homeAway: String?
    var team: SoccerTeamRef?
    var score: String?
}

struct SoccerHeaderStatus: Codable {
    var type: SoccerHeaderStatusType?
}

struct SoccerHeaderStatusType: Codable {
    /// "pre", "in" or "post".
    var state: String?
    var completed: Bool?
    /// e.g. "STATUS_HALFTIME".
    var name: String?
    /// e.g. "HT", "67'".
    var shortDetail: String?
}

struct SoccerBoxscore: Codable {
    var teams: [SoccerBoxscoreTeam]?
}

struct SoccerBoxscoreTeam: Codable {
    var team: SoccerTeamRef?
    var statistics: [SoccerTeamStatistic]?
    var homeAway: String?
}

struct SoccerTeamStatistic: Codable {
    var name: String?
    var displayValue: String?
    var label: String?
}

struct SoccerRoster: Codable {
    var homeAway: String?
    var team: SoccerTeamRef?
    var formation: String?
    var roster: [SoccerRosterPlayer]?
}

struct SoccerRosterPlayer: Codable {
    var starter: Bool?
    var jersey: String?
    var subbedIn: Bool?
    var subbedOut: Bool?
    var formationPlace: String?
    var athlete: SoccerAthlete?
    var position: SoccerPosition?
    var stats: [SoccerPlayerStatistic]?
}

struct SoccerAthlete: Codable {
    var id: String?
    var displayName: String?
    var shortName: String?
}

struct SoccerPosition: Codable {
    var name: String?
    var abbreviation: String?
}

struct SoccerPlayerStatistic: Codable {
    var name: String?
    var displayName: String?
    var shortDisplayName: String?
    var abbreviation: String?
    var value: Double?
    var displayValue: String?
}

struct SoccerTeamRef: Codable {
    var id: String?
    var displayName: String?
    var abbreviation: String?
    var logo: String?
    var logos: [SoccerLogo]?

    var badge: String? { logo ?? logos?.first?.href }
}

struct SoccerLogo: Codable {
    var href: String?
}

struct SoccerKeyEvent: Codable {
    var id: String?
    var type: SoccerEventType?
    var text: String?
    var shortText: String?
    var period: SoccerEventPeriod?
    var clock: SoccerEventClock?
    var scoringPlay: Bool?
    var team: SoccerTeamRef?
    var participants: [SoccerEventParticipant]?
}

struct SoccerEventType: Codable {
    var id: String?
    var text: String?
    var type: String?
}

struct SoccerEventPeriod: Codable { var number: Int? }
struct SoccerEventClock: Codable {
    /// Seconds since kickoff, running through stoppage time.
    var value: Double?
    var displayValue: String?
}
struct SoccerEventParticipant: Codable { var athlete: SoccerAthlete? }

struct SoccerCommentary: Codable {
    var sequence: Int?
    var time: SoccerEventClock?
    var text: String?
    var play: SoccerCommentaryPlay?
}

struct SoccerCommentaryPlay: Codable {
    var id: String?
    var type: SoccerEventType?
    var period: SoccerEventPeriod?
    var clock: SoccerEventClock?
    /// Commentary team refs carry only `displayName`.
    var team: SoccerTeamRef?
    var participants: [SoccerEventParticipant]?
    var fieldPositionX: Double?
    var fieldPositionY: Double?
    var goalPositionY: Double?
}

/// One side's list of games — `lastFiveGames` and `headToHeadGames` share it.
struct SoccerTeamGames: Codable {
    var team: SoccerTeamRef?
    var events: [SoccerTeamGame]?
}

struct SoccerTeamGame: Codable {
    var id: String?
    var gameDate: String?
    var homeTeamId: String?
    var awayTeamId: String?
    var homeTeamScore: String?
    var awayTeamScore: String?
    /// "W", "D" or "L" from `team`'s view.
    var gameResult: String?
    var leagueAbbreviation: String?
    var opponent: SoccerTeamRef?
}

struct SoccerSeasonSeries: Codable {
    var type: String?
    var summary: String?
    var events: [SoccerSeriesEvent]?
}

struct SoccerSeriesEvent: Codable {
    var id: String?
    var date: String?
    var competitors: [SoccerSeriesCompetitor]?
}

struct SoccerSeriesCompetitor: Codable {
    var homeAway: String?
    var team: SoccerTeamRef?
    var score: String?
}

extension SoccerSummaryResponse {
    /// ESPN's match state: "pre", "in" or "post". Nil when the header is missing.
    var matchState: String? { header?.competitions?.first?.status?.type?.state }
}

// MARK: - Builder

enum SoccerMatchBuilder {
    /// Team-stat keys we surface, in display order. Everything else ESPN returns
    /// (crosses, long balls, clearances…) is dropped to keep the comparison readable.
    private static let teamStatOrder: [String] = [
        "possessionPct", "totalShots", "shotsOnTarget", "blockedShots", "totalPasses", "passPct",
        "wonCorners", "totalTackles", "interceptions", "foulsCommitted", "offsides",
        "saves", "yellowCards", "redCards"
    ]

    /// Per-player stat keys we keep, in display order. Trimmed from ESPN's ~14 so
    /// the lineup lines read like a box score rather than a data dump.
    private static let playerStatOrder: [String] = [
        "totalGoals", "goalAssists", "ownGoals", "totalShots", "shotsOnTarget",
        "saves", "goalsConceded", "foulsCommitted", "foulsSuffered", "yellowCards", "redCards", "offsides"
    ]

    static func build(from summary: SoccerSummaryResponse, eventID: String) -> SoccerMatchDetail? {
        let rosters = summary.rosters ?? []
        let homeRoster = rosters.first { $0.homeAway == "home" }
        let awayRoster = rosters.first { $0.homeAway == "away" }

        let boxTeams = summary.boxscore?.teams ?? []
        let homeBox = boxTeams.first { $0.homeAway == "home" }
        let awayBox = boxTeams.first { $0.homeAway == "away" }

        // Prefer roster team refs (carry logos[]); then the box score; then the
        // header, which is the only one present for a lower-tier cup tie.
        let headerTeams = summary.header?.competitions?.first?.competitors ?? []
        let homeTeamRef = homeRoster?.team ?? homeBox?.team ?? headerTeams.first { $0.homeAway == "home" }?.team
        let awayTeamRef = awayRoster?.team ?? awayBox?.team ?? headerTeams.first { $0.homeAway == "away" }?.team

        var home = makeTeam(roster: homeRoster, fallback: homeTeamRef)
        var away = makeTeam(roster: awayRoster, fallback: awayTeamRef)
        home.form = makeForm(summary.lastFiveGames ?? [], teamID: homeTeamRef?.id)
        away.form = makeForm(summary.lastFiveGames ?? [], teamID: awayTeamRef?.id)

        let sides = SideResolver(home: homeTeamRef, away: awayTeamRef)
        let commentary = summary.commentary ?? []

        let detail = SoccerMatchDetail(
            eventID: eventID,
            home: home,
            away: away,
            teamStats: makeTeamStats(home: homeBox, away: awayBox),
            events: makeEvents(summary.keyEvents ?? [], sides: sides),
            shots: makeShots(commentary, sides: sides),
            momentum: makeMomentum(commentary, sides: sides, isFinished: summary.matchState == "post"),
            commentary: makeCommentary(commentary, sides: sides),
            headToHead: makeHeadToHead(summary, homeTeamID: homeTeamRef?.id),
            status: makeStatus(summary)
        )
        return detail.isEmpty ? nil : detail
    }

    private static func makeStatus(_ summary: SoccerSummaryResponse) -> SoccerMatchStatus? {
        let competition = summary.header?.competitions?.first
        guard let type = competition?.status?.type, let state = type.state else { return nil }
        let score = { (side: String) in
            competition?.competitors?.first { $0.homeAway == side }?.score.flatMap(Int.init)
        }
        return SoccerMatchStatus(
            state: state, name: type.name, detail: type.shortDetail,
            homeScore: score("home"), awayScore: score("away")
        )
    }

    // MARK: Lineups

    private static func makeTeam(roster: SoccerRoster?, fallback: SoccerTeamRef?) -> SoccerLineup {
        let players = (roster?.roster ?? []).map(makePlayer).sorted { lhs, rhs in
            // Starters first (by formation place), then everyone else by name.
            if lhs.starter != rhs.starter { return lhs.starter && !rhs.starter }
            if lhs.starter, let l = lhs.formationPlace, let r = rhs.formationPlace, l != r { return l < r }
            return lhs.name < rhs.name
        }
        return SoccerLineup(
            teamID: fallback?.id,
            teamName: fallback?.displayName ?? "",
            teamBadge: fallback?.badge,
            formation: roster?.formation,
            players: players
        )
    }

    private static func makePlayer(_ p: SoccerRosterPlayer) -> SoccerLineupPlayer {
        let byName = Dictionary(
            (p.stats ?? []).compactMap { stat -> (String, SoccerPlayerStatistic)? in
                guard let name = stat.name else { return nil }
                return (name, stat)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let stats: [SoccerPlayerStat] = playerStatOrder.compactMap { key in
            guard let stat = byName[key], let display = stat.displayValue else { return nil }
            return SoccerPlayerStat(
                name: key,
                abbreviation: stat.abbreviation ?? stat.shortDisplayName,
                displayName: stat.displayName,
                value: stat.value,
                displayValue: display
            )
        }
        let starter = p.starter ?? false
        // ESPN numbers substitutes' formationPlace 0; only starters have a slot.
        let place = p.formationPlace.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
        return SoccerLineupPlayer(
            athleteID: p.athlete?.id,
            name: p.athlete?.displayName ?? p.athlete?.shortName ?? "—",
            shortName: p.athlete?.shortName,
            jersey: p.jersey,
            position: p.position?.abbreviation,
            positionName: p.position?.name,
            starter: starter,
            subbedIn: p.subbedIn ?? false,
            subbedOut: p.subbedOut ?? false,
            formationPlace: starter ? place : nil,
            stats: stats
        )
    }

    // MARK: Team stat comparison

    private static func makeTeamStats(home: SoccerBoxscoreTeam?, away: SoccerBoxscoreTeam?) -> [SoccerTeamStat] {
        let homeByName = statMap(home)
        let awayByName = statMap(away)
        return teamStatOrder.compactMap { key in
            guard let h = homeByName[key], let a = awayByName[key] else { return nil }
            let label = h.label ?? a.label ?? key
            let homeDisplay = formatTeamStat(key: key, value: h.displayValue ?? "")
            let awayDisplay = formatTeamStat(key: key, value: a.displayValue ?? "")
            return SoccerTeamStat(
                name: key,
                label: label,
                homeDisplay: homeDisplay,
                awayDisplay: awayDisplay,
                homeValue: numericValue(key: key, display: h.displayValue),
                awayValue: numericValue(key: key, display: a.displayValue)
            )
        }
    }

    private static func statMap(_ team: SoccerBoxscoreTeam?) -> [String: SoccerTeamStatistic] {
        Dictionary(
            (team?.statistics ?? []).compactMap { stat -> (String, SoccerTeamStatistic)? in
                guard let name = stat.name else { return nil }
                return (name, stat)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// ESPN gives pass accuracy as a fraction ("0.84"); show it as a percentage.
    private static func formatTeamStat(key: String, value: String) -> String {
        guard !value.isEmpty else { return value }
        switch key {
        case "possessionPct": return "\(value)%"
        case "passPct":
            guard let fraction = Double(value) else { return value }
            return "\(Int((fraction <= 1 ? fraction * 100 : fraction).rounded()))%"
        default: return value
        }
    }

    private static func numericValue(key: String, display: String?) -> Double? {
        guard let value = display.flatMap(Double.init) else { return nil }
        return key == "passPct" && value <= 1 ? value * 100 : value
    }

    // MARK: Event timeline

    private static func makeEvents(_ raw: [SoccerKeyEvent], sides: SideResolver) -> [SoccerMatchEvent] {
        raw.compactMap { event -> SoccerMatchEvent? in
            let typeText = event.type?.text ?? ""
            guard let mapped = mapEventType(text: typeText, espnType: event.type?.type) else { return nil }
            return SoccerMatchEvent(
                id: event.id ?? UUID().uuidString,
                type: mapped,
                typeText: typeText,
                clock: event.clock?.displayValue?.isEmpty == false ? event.clock?.displayValue : nil,
                period: event.period?.number,
                side: sides.side(of: event.team),
                scoringPlay: event.scoringPlay ?? false,
                text: event.text,
                shortText: event.shortText,
                playerNames: (event.participants ?? []).compactMap { $0.athlete?.displayName }
            )
        }
    }

    /// Keep only the events worth a timeline row: goals, cards, subs. Kickoff /
    /// halftime / delays return nil and are filtered out.
    private static func mapEventType(text: String, espnType: String?) -> SoccerMatchEventType? {
        let lower = (espnType ?? text).lowercased()
        if lower.contains("own") && lower.contains("goal") { return .ownGoal }
        if lower.contains("penalty") && (lower.contains("miss") || lower.contains("saved")) { return .penaltyMissed }
        if lower.contains("penalty") && (lower.contains("goal") || lower.contains("scored")) { return .penaltyGoal }
        if lower.contains("goal") { return .goal }
        if lower.contains("yellow") { return .yellowCard }
        if lower.contains("red") { return .redCard }
        if lower.contains("substitution") || lower == "sub" { return .substitution }
        return nil
    }

    // MARK: Shots

    private static func makeShots(_ commentary: [SoccerCommentary], sides: SideResolver) -> [SoccerShot] {
        commentary.compactMap { entry -> SoccerShot? in
            guard let play = entry.play,
                  let typeKey = play.type?.type,
                  let x = play.fieldPositionX, let y = play.fieldPositionY,
                  let side = sides.side(of: play.team) else { return nil }
            let text = entry.text ?? ""
            guard let outcome = SoccerShotText.outcome(typeKey: typeKey, text: text) else { return nil }
            let bodyPart = SoccerShotText.bodyPart(text)
            let situation = SoccerShotText.situation(text, typeKey: typeKey)
            let xG = SoccerExpectedGoals.estimate(x: x, y: y, bodyPart: bodyPart, situation: situation)
            return SoccerShot(
                id: play.id ?? "\(entry.sequence ?? 0)",
                side: side,
                playerName: play.participants?.first?.athlete?.displayName,
                clock: entry.time?.displayValue ?? "",
                minute: (entry.time?.value ?? 0) / 60,
                period: play.period?.number,
                outcome: outcome,
                bodyPart: bodyPart,
                situation: situation,
                x: x,
                y: y,
                goalMouthY: play.goalPositionY,
                xG: (xG * 100).rounded() / 100
            )
        }
    }

    // MARK: Momentum

    /// Match minute each period's regulation time ends at.
    private static let periodEndMinute = [1: 45, 2: 90, 3: 105, 4: 120]

    private static func makeMomentum(_ commentary: [SoccerCommentary], sides: SideResolver, isFinished: Bool) -> [SoccerMomentumPoint] {
        // Period-boundary rows carry no period, so carry the last one forward.
        var period = 1
        let actions = commentary.compactMap { entry -> SoccerMomentum.Action? in
            if let number = entry.play?.period?.number { period = number }
            guard let play = entry.play, let typeKey = play.type?.type,
                  let x = play.fieldPositionX,
                  let side = sides.side(of: play.team) else { return nil }
            let minute = (entry.time?.value ?? 0) / 60
            let text = entry.text ?? ""
            if typeKey == "own-goal" { return nil }
            if let outcome = SoccerShotText.outcome(typeKey: typeKey, text: text) {
                return .init(minute: minute, period: period, side: side, x: x, kind: outcome == .goal ? .goal : .shot)
            }
            switch typeKey {
            case "corner-awarded":
                return .init(minute: minute, period: period, side: side, x: x, kind: .corner)
            case "offside":
                return .init(minute: minute, period: period, side: side, x: x, kind: .offside)
            case "foul", "handball":
                // The team on these rows is the offender, located from its own view;
                // the pressure belongs to the side that won the free kick.
                return .init(minute: minute, period: period, side: side.opposite, x: 100 - x, kind: .freeKickWon)
            default:
                return nil
            }
        }
        // Every period but the one in play has finished, so its run reaches full time.
        let latest = actions.map(\.period).max() ?? 1
        var lastMinutes: [Int: Int] = [:]
        for (p, end) in periodEndMinute where p < latest || (p == latest && isFinished) {
            lastMinutes[p] = end
        }
        return SoccerMomentum.compute(actions, lastMinutes: lastMinutes)
    }

    // MARK: Commentary

    private static func makeCommentary(_ raw: [SoccerCommentary], sides: SideResolver) -> [SoccerCommentaryEntry] {
        raw.compactMap { entry -> SoccerCommentaryEntry? in
            guard let text = entry.text, !text.isEmpty else { return nil }
            let typeKey = entry.play?.type?.type ?? ""
            let clock = entry.time?.displayValue
            return SoccerCommentaryEntry(
                id: entry.play?.id ?? "c\(entry.sequence ?? 0)",
                clock: clock?.isEmpty == false ? clock : nil,
                text: text,
                kind: commentaryKind(typeKey),
                side: sides.side(of: entry.play?.team)
            )
        }
    }

    private static func commentaryKind(_ typeKey: String) -> SoccerCommentaryKind {
        if typeKey.hasPrefix("goal") || typeKey == "own-goal" || typeKey == "penalty---scored" { return .goal }
        if typeKey.hasPrefix("shot") || typeKey.hasPrefix("penalty") { return .chance }
        if typeKey.contains("card") { return .card }
        if typeKey == "substitution" { return .substitution }
        if typeKey.hasPrefix("var") || typeKey == "deleted-after-review" { return .var }
        switch typeKey {
        case "kickoff", "halftime", "start-2nd-half", "end-regular-time", "start-extra-time",
             "end-extra-time", "end-of-game", "full-time":
            return .periodBoundary
        default:
            return .other
        }
    }

    // MARK: Form and head-to-head

    private static func makeForm(_ lists: [SoccerTeamGames], teamID: String?) -> [SoccerFormMatch] {
        guard let teamID, let list = lists.first(where: { $0.team?.id == teamID }) else { return [] }
        let form = (list.events ?? []).compactMap { game -> SoccerFormMatch? in
            guard let id = game.id,
                  let result = game.gameResult.flatMap(SoccerResult.init(rawValue:)),
                  let homeScore = game.homeTeamScore.flatMap(Int.init),
                  let awayScore = game.awayTeamScore.flatMap(Int.init) else { return nil }
            let isHome = game.homeTeamId == teamID
            return SoccerFormMatch(
                eventID: id,
                date: game.gameDate.flatMap(DateParsers.parse),
                result: result,
                goalsFor: isHome ? homeScore : awayScore,
                goalsAgainst: isHome ? awayScore : homeScore,
                isHome: isHome,
                opponentName: game.opponent?.displayName ?? "",
                opponentAbbreviation: game.opponent?.abbreviation,
                opponentBadge: game.opponent?.badge,
                competition: game.leagueAbbreviation
            )
        }
        return form.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    private static func makeHeadToHead(_ summary: SoccerSummaryResponse, homeTeamID: String?) -> SoccerHeadToHead? {
        if let series = summary.seasonseries?.first(where: { $0.type == "head-to-head" }) ?? summary.seasonseries?.first {
            let matches = (series.events ?? []).compactMap { event -> SoccerPastMeeting? in
                guard let id = event.id,
                      let home = event.competitors?.first(where: { $0.homeAway == "home" }),
                      let away = event.competitors?.first(where: { $0.homeAway == "away" }) else { return nil }
                return SoccerPastMeeting(
                    eventID: id,
                    date: event.date.flatMap(DateParsers.parse),
                    homeName: home.team?.displayName ?? "",
                    awayName: away.team?.displayName ?? "",
                    homeAbbreviation: home.team?.abbreviation,
                    awayAbbreviation: away.team?.abbreviation,
                    homeScore: home.score.flatMap(Int.init),
                    awayScore: away.score.flatMap(Int.init)
                )
            }
            return matches.isEmpty ? nil : SoccerHeadToHead(summary: series.summary, matches: matches)
        }

        // International fixtures: one side's list of past meetings with the other.
        guard let list = summary.headToHeadGames?.first, let team = list.team else { return nil }
        let matches = (list.events ?? []).compactMap { game -> SoccerPastMeeting? in
            guard let id = game.id, let opponent = game.opponent else { return nil }
            let teamIsHome = game.homeTeamId == team.id
            return SoccerPastMeeting(
                eventID: id,
                date: game.gameDate.flatMap(DateParsers.parse),
                homeName: (teamIsHome ? team.displayName : opponent.displayName) ?? "",
                awayName: (teamIsHome ? opponent.displayName : team.displayName) ?? "",
                homeAbbreviation: teamIsHome ? team.abbreviation : opponent.abbreviation,
                awayAbbreviation: teamIsHome ? opponent.abbreviation : team.abbreviation,
                homeScore: game.homeTeamScore.flatMap(Int.init),
                awayScore: game.awayTeamScore.flatMap(Int.init)
            )
        }
        return matches.isEmpty ? nil : SoccerHeadToHead(matches: matches)
    }
}

// MARK: - Side resolution

/// Works out home/away from a team ref. Key events carry team ids; commentary rows
/// carry only a display name, so both are matched.
private struct SideResolver {
    let home: SoccerTeamRef?
    let away: SoccerTeamRef?

    func side(of team: SoccerTeamRef?) -> BracketSide? {
        guard let team else { return nil }
        if let id = team.id {
            if id == home?.id { return .home }
            if id == away?.id { return .away }
        }
        if let name = team.displayName {
            if name == home?.displayName { return .home }
            if name == away?.displayName { return .away }
        }
        return nil
    }
}

private extension BracketSide {
    var opposite: BracketSide { self == .home ? .away : .home }
}
