//
//  SoccerPlayerBuilder.swift
//  SportsCalServer
//
//  Decodes ESPN's soccer athlete bio and overview and maps them onto the shared
//  `SoccerPlayerProfile`. ESPN ships the overview's stat tables as parallel
//  arrays (`names`/`labels` once, then a `stats` string array per row), so each
//  row is zipped back into named stats here.
//

import Foundation
import SportsCalModel

// MARK: - ESPN decode (only the fields we consume)

struct SoccerAthleteResponse: Decodable {
    var athlete: Athlete?

    struct Athlete: Decodable {
        var id: String?
        var displayName: String?
        var jersey: String?
        var age: Int?
        var displayHeight: String?
        var citizenship: String?
        var position: Position?
        var team: Team?
        var flag: Flag?
    }

    struct Position: Decodable { var displayName: String? }
    struct Team: Decodable { var id: String?; var displayName: String? }
    struct Flag: Decodable { var href: String? }
}

struct SoccerAthleteOverview: Decodable {
    var statistics: StatTable?
    var gameLog: GameLog?
    var nextGame: NextGame?

    struct StatTable: Decodable {
        var names: [String]?
        var labels: [String]?
        var displayNames: [String]?
        var splits: [Split]?
    }

    struct Split: Decodable {
        var displayName: String?
        var leagueSlug: String?
        var stats: [String]?
    }

    struct GameLog: Decodable {
        var statistics: [GameLogTable]?
        /// Event id → match details.
        var events: [String: GameLogEvent]?
    }

    struct GameLogTable: Decodable {
        var names: [String]?
        var labels: [String]?
        var displayNames: [String]?
        var events: [GameLogRow]?
    }

    struct GameLogRow: Decodable {
        var eventId: String?
        var stats: [String]?
    }

    struct GameLogEvent: Decodable {
        var id: String?
        var gameDate: String?
        var homeTeamId: String?
        var homeTeamScore: String?
        var awayTeamScore: String?
        var gameResult: String?
        var leagueAbbreviation: String?
        var leagueName: String?
        var opponent: Opponent?
    }

    struct Opponent: Decodable {
        var id: String?
        var displayName: String?
        var abbreviation: String?
    }

    struct NextGame: Decodable {
        var league: NextGameLeague?
    }

    struct NextGameLeague: Decodable {
        var shortName: String?
        var events: [NextGameEvent]?
    }

    struct NextGameEvent: Decodable {
        var id: String?
        var date: String?
        var name: String?
    }
}

// MARK: - Builder

enum SoccerPlayerBuilder {
    static func build(athleteID: String, bio: SoccerAthleteResponse?, overview: SoccerAthleteOverview?) -> SoccerPlayerProfile? {
        let athlete = bio?.athlete
        guard let name = athlete?.displayName else { return nil }
        return SoccerPlayerProfile(
            athleteID: athleteID,
            name: name,
            position: athlete?.position?.displayName,
            jersey: athlete?.jersey,
            age: athlete?.age,
            height: athlete?.displayHeight,
            nationality: athlete?.citizenship,
            flagURL: athlete?.flag?.href,
            teamID: athlete?.team?.id,
            teamName: athlete?.team?.displayName,
            seasons: makeSeasons(overview?.statistics),
            recentMatches: makeRecentMatches(overview?.gameLog),
            nextMatch: makeNextMatch(overview?.nextGame)
        )
    }

    // MARK: Season lines

    private static func makeSeasons(_ table: SoccerAthleteOverview.StatTable?) -> [SoccerPlayerSeason] {
        guard let table, let names = table.names else { return [] }
        return (table.splits ?? []).compactMap { split in
            guard let competition = split.displayName, let values = split.stats else { return nil }
            return SoccerPlayerSeason(
                competition: competition,
                leagueSlug: split.leagueSlug,
                stats: zipStats(names: names, labels: table.labels, displayNames: table.displayNames, values: values)
            )
        }
    }

    // MARK: Recent matches

    private static func makeRecentMatches(_ log: SoccerAthleteOverview.GameLog?) -> [SoccerPlayerMatch] {
        guard let table = log?.statistics?.first, let names = table.names else { return [] }
        let events = log?.events ?? [:]
        // ESPN repeats some rows (seen with Nations League matches); keep the first.
        var seen = Set<String>()
        let matches = (table.events ?? []).compactMap { row -> SoccerPlayerMatch? in
            guard let id = row.eventId, seen.insert(id).inserted,
                  let event = events[id], let opponent = event.opponent,
                  let values = row.stats else { return nil }
            // The player's side is whichever isn't the opponent.
            let isHome = event.homeTeamId != opponent.id
            let home = event.homeTeamScore.flatMap(Int.init)
            let away = event.awayTeamScore.flatMap(Int.init)
            let stats = zipStats(names: names, labels: table.labels, displayNames: table.displayNames, values: values)
            return SoccerPlayerMatch(
                eventID: id,
                date: event.gameDate.flatMap(DateParsers.parse),
                opponentName: opponent.displayName ?? "",
                opponentAbbreviation: opponent.abbreviation,
                isHome: isHome,
                result: event.gameResult.flatMap(SoccerResult.init(rawValue:)),
                goalsFor: isHome ? home : away,
                goalsAgainst: isHome ? away : home,
                competition: event.leagueAbbreviation ?? event.leagueName,
                // The first column is the appearance itself: "Started" / "Substitute".
                appearance: values.first.flatMap { Double($0) == nil ? $0 : nil },
                stats: stats.filter { $0.name != "appearances" }
            )
        }
        return matches.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private static func makeNextMatch(_ next: SoccerAthleteOverview.NextGame?) -> SoccerPlayerFixture? {
        guard let event = next?.league?.events?.first, let id = event.id, let name = event.name else { return nil }
        return SoccerPlayerFixture(
            eventID: id,
            date: event.date.flatMap(DateParsers.parse),
            name: name,
            competition: next?.league?.shortName
        )
    }

    // MARK: Helpers

    /// Zips one row of ESPN's parallel arrays into named stats. Non-numeric cells
    /// (the "Started" appearance column) keep their text with no value.
    static func zipStats(names: [String], labels: [String]?, displayNames: [String]?, values: [String]) -> [SoccerPlayerStat] {
        zip(names.indices, zip(names, values)).map { index, pair in
            let (name, value) = pair
            return SoccerPlayerStat(
                name: name,
                abbreviation: labels?[safe: index],
                displayName: displayNames?[safe: index],
                value: Double(value),
                displayValue: value
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
