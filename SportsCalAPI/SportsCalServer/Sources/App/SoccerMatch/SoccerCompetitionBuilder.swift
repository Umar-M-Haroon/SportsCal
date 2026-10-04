//
//  SoccerCompetitionBuilder.swift
//  SportsCalServer
//
//  Builds a `SoccerCompetitionHub` from three ESPN responses: the standings (table,
//  zones, rank change), the season scoreboard (each side's last five results — ESPN's
//  table has no form column) and the league statistics (scorers and assisters).
//

import Foundation
import SportsCalModel

enum SoccerCompetitionBuilder {
    /// How many scorers / assisters the hub carries.
    static let leaderCount = 20

    static func build(
        leagueID: Int,
        standings: StandingsResponse?,
        season: [Event],
        statistics: LeagueStatisticsResponse?
    ) -> SoccerCompetitionHub {
        let form = SoccerForm.lastResults(formResults(season))
        let children = (standings?.children ?? []).filter { !($0.standings?.entries ?? []).isEmpty }
        let groups = children.map { child in
            SoccerTableGroup(
                // A league's single table needs no heading; a group stage's do.
                name: children.count > 1 ? child.name : nil,
                rows: (child.standings?.entries ?? []).enumerated().compactMap { index, entry in
                    makeRow(entry, fallbackRank: index + 1, form: form)
                }.sorted { $0.rank < $1.rank }
            )
        }
        return SoccerCompetitionHub(
            leagueID: leagueID,
            groups: groups,
            scorers: makeLeaders(statistics, category: "goalsLeaders"),
            assisters: makeLeaders(statistics, category: "assistsLeaders")
        )
    }

    // MARK: Table

    private static func makeRow(_ entry: Entry, fallbackRank: Int, form: [String: [SoccerResult]]) -> SoccerTableRow? {
        guard let team = entry.team, let teamID = team.id else { return nil }
        let stats = Dictionary(
            (entry.stats ?? []).compactMap { stat in stat.name.map { ($0, stat) } },
            uniquingKeysWith: { first, _ in first }
        )
        func int(_ name: String) -> Int {
            if let value = stats[name]?.value { return Int(value) }
            return Int(stats[name]?.displayValue?.replacingOccurrences(of: "+", with: "") ?? "") ?? 0
        }
        let zone = entry.note.flatMap { note -> SoccerTableZone? in
            guard let description = note.description, let color = note.color else { return nil }
            return SoccerTableZone(description: description, colorHex: color)
        }
        let rank = int("rank")
        return SoccerTableRow(
            rank: rank > 0 ? rank : fallbackRank,
            teamID: teamID,
            teamName: team.displayName ?? team.name ?? "",
            abbreviation: team.abbreviation,
            badge: team.logos?.first?.href,
            played: int("gamesPlayed"),
            won: int("wins"),
            drawn: int("ties"),
            lost: int("losses"),
            goalsFor: int("pointsFor"),
            goalsAgainst: int("pointsAgainst"),
            points: int("points"),
            rankChange: int("rankChange"),
            zone: zone,
            form: form[teamID] ?? []
        )
    }

    /// Finished matches from the season scoreboard, as form inputs. A calendar-year
    /// board spans two seasons (Jan–May of the last, Aug–Dec of this one); only the
    /// latest counts, so a promoted side's form doesn't reach back into last season.
    static func formResults(_ events: [Event]) -> [SoccerForm.Result] {
        let latestSeason = events.compactMap { $0.season?.year }.max()
        return events.compactMap { event -> SoccerForm.Result? in
            guard event.status?.type.completed == true,
                  latestSeason == nil || event.season?.year == latestSeason,
                  let date = DateParsers.parse(event.date),
                  let competitors = event.competitions?.first?.competitors,
                  let home = competitors.first(where: { $0.homeAway == "home" }),
                  let away = competitors.first(where: { $0.homeAway == "away" }),
                  let homeScore = home.score.flatMap(Int.init),
                  let awayScore = away.score.flatMap(Int.init) else { return nil }
            return SoccerForm.Result(date: date, homeID: home.id, awayID: away.id,
                                     homeScore: homeScore, awayScore: awayScore)
        }
    }

    // MARK: Leaders

    private static func makeLeaders(_ statistics: LeagueStatisticsResponse?, category: String) -> [SoccerLeader] {
        let leaders = statistics?.stats?.first { $0.name == category }?.leaders ?? []
        return leaders.prefix(leaderCount).enumerated().compactMap { index, leader in
            guard let athlete = leader.athlete, let id = athlete.id else { return nil }
            let line = Dictionary(
                (athlete.statistics ?? []).compactMap { stat in stat.name.map { ($0, Int(stat.value ?? 0)) } },
                uniquingKeysWith: { first, _ in first }
            )
            return SoccerLeader(
                rank: index + 1,
                athleteID: id,
                name: athlete.displayName ?? athlete.shortName ?? "",
                teamName: athlete.team?.displayName,
                teamBadge: athlete.team?.logos?.first?.href,
                goals: line["totalGoals"] ?? 0,
                assists: line["goalAssists"] ?? 0,
                appearances: line["appearances"] ?? 0
            )
        }
    }
}
