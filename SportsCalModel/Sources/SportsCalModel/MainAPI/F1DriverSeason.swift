//
//  F1DriverSeason.swift
//  SportsCalModel
//

import Foundation

/// One driver's season rebuilt from the race weekends already in the schedule: finishing
/// positions, qualifying, and points by round. Points are computed from classified
/// positions, so they can drift from the official table after penalties or
/// disqualifications; show `F1Standings` for the official total.
public struct F1DriverSeason: Equatable {
    public struct Round: Equatable, Identifiable {
        public var id: String { gameID }
        public let gameID: String
        public let raceName: String
        public let date: Date?
        public let qualifying: Int?
        public let sprint: Int?
        public let race: Int?
        public let points: Int
        public let cumulativePoints: Int
        public let headshot: String?
        public let constructor: String?
    }

    public let driverName: String
    public let rounds: [Round]

    public var wins: Int { rounds.filter { $0.race == 1 }.count }
    public var podiums: Int { rounds.filter { ($0.race ?? 99) <= 3 }.count }
    public var bestFinish: Int? { rounds.compactMap(\.race).min() }
    public var averageFinish: Double? {
        let finishes = rounds.compactMap(\.race)
        return finishes.isEmpty ? nil : Double(finishes.reduce(0, +)) / Double(finishes.count)
    }

    public static func racePoints(_ position: Int) -> Int {
        let table = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
        return (1...table.count).contains(position) ? table[position - 1] : 0
    }

    public static func sprintPoints(_ position: Int) -> Int {
        (1...8).contains(position) ? 9 - position : 0
    }

    /// - Parameters:
    ///   - driverName: as written in standings (Jolpica); matched to ESPN leaderboard names
    ///     by folded full name, then by unique surname.
    ///   - weekends: F1 games (one per Grand Prix). Only finished sessions count.
    public init(driverName: String, weekends: [Game]) {
        self.driverName = driverName
        let ordered = weekends.sorted { ($0.isoDate ?? .distantPast) < ($1.isoDate ?? .distantPast) }
        var total = 0
        var rounds: [Round] = []
        for weekend in ordered {
            guard let sessions = weekend.sessions else { continue }
            func finished(_ types: Set<String>) -> EventSession? {
                sessions.first { types.contains($0.sessionType.lowercased()) && $0.status == "post" }
            }
            let race = finished(["race", "r"])
            let sprint = finished(["sr", "sprint"])
            let quali = finished(["qual", "qualifying"])
            guard race != nil || sprint != nil else { continue }

            let raceEntry = race.flatMap { Self.entry(for: driverName, in: $0.leaderboard) }
            let sprintEntry = sprint.flatMap { Self.entry(for: driverName, in: $0.leaderboard) }
            let qualiEntry = quali.flatMap { Self.entry(for: driverName, in: $0.leaderboard) }
            guard raceEntry != nil || sprintEntry != nil else { continue }

            let racePosition = raceEntry.map(\.position).flatMap { $0 > 0 ? $0 : nil }
            let sprintPosition = sprintEntry.map(\.position).flatMap { $0 > 0 ? $0 : nil }
            let points = (racePosition.map(Self.racePoints) ?? 0) + (sprintPosition.map(Self.sprintPoints) ?? 0)
            total += points
            rounds.append(Round(
                gameID: weekend.idEvent ?? weekend.strHomeTeam,
                raceName: weekend.strHomeTeam,
                date: weekend.isoDate,
                qualifying: qualiEntry.map(\.position).flatMap { $0 > 0 ? $0 : nil },
                sprint: sprintPosition,
                race: racePosition,
                points: points,
                cumulativePoints: total,
                headshot: (raceEntry ?? sprintEntry)?.headshot,
                constructor: (raceEntry ?? sprintEntry)?.constructor
            ))
        }
        self.rounds = rounds
    }

    static func entry(for driverName: String, in leaderboard: [LeaderboardEntry]) -> LeaderboardEntry? {
        let key = F1Standings.driverKey(driverName)
        if let exact = leaderboard.first(where: { F1Standings.driverKey($0.name) == key }) { return exact }
        let surname = key.split(separator: " ").last.map(String.init)
        let hits = leaderboard.filter { F1Standings.driverKey($0.name).split(separator: " ").last.map(String.init) == surname }
        return hits.count == 1 ? hits.first : nil
    }
}
