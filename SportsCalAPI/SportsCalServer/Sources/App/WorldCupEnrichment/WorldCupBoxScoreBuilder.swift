//
//  WorldCupBoxScoreBuilder.swift
//  SportsCalServer
//
//  Decodes the slice of ESPN's per-event `summary` endpoint we need for a World
//  Cup match box score (team stat comparison, lineups with per-player stats, and
//  the goal/card/sub timeline) and maps it onto the shared `WorldCupBoxScore`.
//
//  Fetched on demand via `/worldcup/boxscore/:eventID` — see routes.swift.
//

import Foundation
import Vapor
import SportsCalModel

// MARK: - ESPN summary decode (only the fields we consume)

struct SoccerSummaryResponse: Codable {
    var boxscore: SoccerBoxscore?
    var rosters: [SoccerRoster]?
    var keyEvents: [SoccerKeyEvent]?
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
struct SoccerEventClock: Codable { var displayValue: String? }
struct SoccerEventParticipant: Codable { var athlete: SoccerAthlete? }

// MARK: - Builder

enum WorldCupBoxScoreBuilder {
    /// Team-stat keys we surface, in display order. Everything ESPN returns beyond
    /// this (pass %, long balls, clearances…) is dropped to keep the comparison readable.
    private static let teamStatOrder: [String] = [
        "possessionPct", "totalShots", "shotsOnTarget", "totalPasses",
        "wonCorners", "foulsCommitted", "offsides", "totalTackles",
        "saves", "yellowCards", "redCards"
    ]

    /// Per-player stat keys we keep, in display order. Trimmed from ESPN's ~14 so
    /// the lineup lines read like a box score rather than a data dump.
    private static let playerStatOrder: [String] = [
        "totalGoals", "goalAssists", "ownGoals", "totalShots", "shotsOnTarget",
        "saves", "goalsConceded", "foulsCommitted", "yellowCards", "redCards", "offsides"
    ]

    static func build(from summary: SoccerSummaryResponse, eventID: String) -> WorldCupBoxScore? {
        let rosters = summary.rosters ?? []
        let homeRoster = rosters.first { $0.homeAway == "home" }
        let awayRoster = rosters.first { $0.homeAway == "away" }

        let boxTeams = summary.boxscore?.teams ?? []
        let homeBox = boxTeams.first { $0.homeAway == "home" }
        let awayBox = boxTeams.first { $0.homeAway == "away" }

        // Prefer roster team refs (carry logos[]); fall back to boxscore team refs.
        let homeTeamRef = homeRoster?.team ?? homeBox?.team
        let awayTeamRef = awayRoster?.team ?? awayBox?.team

        let home = makeTeam(roster: homeRoster, fallback: homeTeamRef)
        let away = makeTeam(roster: awayRoster, fallback: awayTeamRef)

        let teamStats = makeTeamStats(home: homeBox, away: awayBox)
        let events = makeEvents(
            summary.keyEvents ?? [],
            homeTeamID: homeTeamRef?.id,
            awayTeamID: awayTeamRef?.id
        )

        let box = WorldCupBoxScore(
            eventID: eventID,
            home: home,
            away: away,
            teamStats: teamStats,
            events: events
        )
        return box.isEmpty ? nil : box
    }

    // MARK: Lineups

    private static func makeTeam(roster: SoccerRoster?, fallback: SoccerTeamRef?) -> WorldCupBoxScoreTeam {
        let players = (roster?.roster ?? []).map(makePlayer).sorted { lhs, rhs in
            // Starters first (by formation place), then everyone else by name.
            if lhs.starter != rhs.starter { return lhs.starter && !rhs.starter }
            return lhs.name < rhs.name
        }
        return WorldCupBoxScoreTeam(
            teamID: fallback?.id,
            teamName: fallback?.displayName ?? "",
            teamBadge: fallback?.badge,
            formation: roster?.formation,
            players: players
        )
    }

    private static func makePlayer(_ p: SoccerRosterPlayer) -> WorldCupBoxScorePlayer {
        let byName = Dictionary(
            (p.stats ?? []).compactMap { stat -> (String, SoccerPlayerStatistic)? in
                guard let name = stat.name else { return nil }
                return (name, stat)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let stats: [WorldCupPlayerStat] = playerStatOrder.compactMap { key in
            guard let stat = byName[key], let display = stat.displayValue else { return nil }
            return WorldCupPlayerStat(
                name: key,
                abbreviation: stat.abbreviation ?? stat.shortDisplayName,
                displayName: stat.displayName,
                value: stat.value,
                displayValue: display
            )
        }
        return WorldCupBoxScorePlayer(
            athleteID: p.athlete?.id,
            name: p.athlete?.displayName ?? p.athlete?.shortName ?? "—",
            jersey: p.jersey,
            position: p.position?.abbreviation,
            positionName: p.position?.name,
            starter: p.starter ?? false,
            subbedIn: p.subbedIn ?? false,
            subbedOut: p.subbedOut ?? false,
            stats: stats
        )
    }

    // MARK: Team stat comparison

    private static func makeTeamStats(home: SoccerBoxscoreTeam?, away: SoccerBoxscoreTeam?) -> [WorldCupTeamStat] {
        let homeByName = statMap(home)
        let awayByName = statMap(away)
        return teamStatOrder.compactMap { key in
            guard let h = homeByName[key], let a = awayByName[key] else { return nil }
            let label = h.label ?? a.label ?? key
            let homeDisplay = formatTeamStat(key: key, value: h.displayValue ?? "")
            let awayDisplay = formatTeamStat(key: key, value: a.displayValue ?? "")
            return WorldCupTeamStat(
                name: key,
                label: label,
                homeDisplay: homeDisplay,
                awayDisplay: awayDisplay,
                homeValue: Double(h.displayValue ?? ""),
                awayValue: Double(a.displayValue ?? "")
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

    private static func formatTeamStat(key: String, value: String) -> String {
        key == "possessionPct" && !value.isEmpty ? "\(value)%" : value
    }

    // MARK: Event timeline

    private static func makeEvents(_ raw: [SoccerKeyEvent], homeTeamID: String?, awayTeamID: String?) -> [WorldCupMatchEvent] {
        raw.compactMap { event -> WorldCupMatchEvent? in
            let typeText = event.type?.text ?? ""
            guard let mapped = mapEventType(text: typeText, espnType: event.type?.type) else { return nil }
            let side: BracketSide?
            switch event.team?.id {
            case let id? where id == homeTeamID: side = .home
            case let id? where id == awayTeamID: side = .away
            default: side = nil
            }
            return WorldCupMatchEvent(
                id: event.id ?? UUID().uuidString,
                type: mapped,
                typeText: typeText,
                clock: event.clock?.displayValue?.isEmpty == false ? event.clock?.displayValue : nil,
                period: event.period?.number,
                side: side,
                scoringPlay: event.scoringPlay ?? false,
                text: event.text,
                shortText: event.shortText,
                playerNames: (event.participants ?? []).compactMap { $0.athlete?.displayName }
            )
        }
    }

    /// Keep only the events worth a timeline row: goals, cards, subs. Kickoff /
    /// halftime / delays return nil and are filtered out.
    private static func mapEventType(text: String, espnType: String?) -> WorldCupMatchEventType? {
        let lower = (espnType ?? text).lowercased()
        if lower.contains("own") && lower.contains("goal") { return .ownGoal }
        if lower.contains("penalty") && lower.contains("miss") { return .penaltyMissed }
        if lower.contains("penalty") && lower.contains("goal") { return .penaltyGoal }
        if lower.contains("goal") { return .goal }
        if lower.contains("yellow") { return .yellowCard }
        if lower.contains("red") { return .redCard }
        if lower.contains("substitution") || lower == "sub" { return .substitution }
        return nil
    }
}
