//
//  PlayerLiveStatLine.swift
//  SportsCalModel
//
//  One player's live numbers for a game, as plain numbers by stat name, built from
//  `boxscore.players` on ESPN's per-event summary (the fetch that feeds the
//  play-by-play). It's what milestone alerts compare against ("reaches 30 points").
//
//  Server-side only: the server keeps these per event in Redis. They never ride on
//  `/schedules`, the live socket or `/plays` (which has its own display-ready
//  `PlayerBoxScore`, opt-in).
//

import Foundation

public struct PlayerLiveStatLine: Codable, Equatable, Hashable, Sendable {
    /// ESPN athlete ID, the same ID as `PlayParticipant.athleteID`.
    public var athleteID: String
    /// "Nikola Jokic".
    public var name: String
    /// ESPN team ID.
    public var teamID: String
    /// Stat name → value. See `PlayerLiveStatLine.lines(boxscore:sport:)` for the names.
    public var stats: [String: Double]

    public init(athleteID: String, name: String, teamID: String, stats: [String: Double]) {
        self.athleteID = athleteID
        self.name = name
        self.teamID = teamID
        self.stats = stats
    }
}

public extension PlayerLiveStatLine {
    /// One line per player who has played, both teams, in ESPN's order.
    ///
    /// Stat names are ESPN's keys:
    /// - Basketball and hockey use them as they are: `points`, `rebounds`, `assists`,
    ///   `threePointFieldGoalsMade`; `goals`, `assists`, `shotsTotal`, `saves`.
    /// - Football and baseball prefix the table, because a player can sit in several and
    ///   the same key means different things in each (an interception thrown vs one
    ///   caught; a pitcher's strikeouts vs his own at the plate): `passing.passingYards`,
    ///   `defensive.sacks`, `batting.homeRuns`, `pitching.strikeouts`.
    /// - Paired columns are split: `fieldGoalsMade-fieldGoalsAttempted` "5-10" becomes
    ///   `fieldGoalsMade` 5 and `fieldGoalsAttempted` 10; `completions/passingAttempts`
    ///   likewise.
    /// - Times ("18:32") are seconds. Innings pitched ("6.1") become
    ///   `pitching.inningsPitched` 6.333 and `pitching.outs` 19.
    /// - Year-to-date columns (`ytdGoals`) and values that aren't numbers ("--") are left out.
    ///
    /// Empty for sports without player tables (soccer, golf, tennis, racing).
    static func lines(boxscore: ESPNSummaryBoxscore?, sport: SportType) -> [PlayerLiveStatLine] {
        guard PlayerBoxScore.supports(sport), let teams = boxscore?.players else { return [] }
        let prefixesGroup = sport == .nfl || sport == .mlb
        var out: [PlayerLiveStatLine] = []
        // (team, athlete) → index in `out`, to merge a player's tables into one line.
        var index: [String: Int] = [:]
        for team in teams {
            guard let teamID = team.team?.id else { continue }
            for group in team.statistics ?? [] {
                let keys = group.keys ?? []
                let groupName = group.name ?? group.type
                for line in group.athletes ?? [] {
                    guard let athlete = line.athlete, let athleteID = athlete.id,
                          line.didNotPlay != true, let values = line.stats, !values.isEmpty else { continue }
                    var stats: [String: Double] = [:]
                    for (position, key) in keys.enumerated() where position < values.count {
                        let prefix = prefixesGroup ? groupName.map { "\($0)." } ?? "" : ""
                        for (name, value) in parse(key: key, value: values[position]) {
                            stats[prefix + name] = stats[prefix + name] ?? value
                        }
                    }
                    guard !stats.isEmpty else { continue }
                    let slot = teamID + "|" + athleteID
                    if let existing = index[slot] {
                        out[existing].stats.merge(stats) { current, _ in current }
                    } else {
                        let name = athlete.displayName ?? athlete.shortName ?? athleteID
                        index[slot] = out.count
                        out.append(PlayerLiveStatLine(athleteID: athleteID, name: name, teamID: teamID, stats: stats))
                    }
                }
            }
        }
        return out
    }

    /// The named numbers in one box-score cell. Usually one; two for a paired column.
    internal static func parse(key: String, value raw: String) -> [(String, Double)] {
        if key.hasPrefix("ytd") { return [] }
        let value = raw.trimmingCharacters(in: .whitespaces)
        if key == "fullInnings.partInnings" {
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard let full = parts.first.flatMap({ Int($0) }), full >= 0 else { return [] }
            let part = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            guard (0...2).contains(part) else { return [] }
            return [("inningsPitched", Double(full) + Double(part) / 3), ("outs", Double(full * 3 + part))]
        }
        for separator in ["-", "/"] where key.contains(separator) {
            let names = key.components(separatedBy: separator)
            let values = value.components(separatedBy: separator)
            guard names.count == values.count, names.allSatisfy({ !$0.isEmpty }) else { return [] }
            var out: [(String, Double)] = []
            for (name, part) in zip(names, values) {
                guard let number = number(part) else { return [] }
                out.append((name, number))
            }
            return out
        }
        return number(value).map { [(key, $0)] } ?? []
    }

    /// "12", "-3", "+5", ".923", "55.6%", "18:32" (→ seconds). Nil for "--", "" and
    /// anything that isn't a finite number.
    internal static func number(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("%") { text.removeLast() }
        if text.contains(":") {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]),
                  minutes >= 0, (0..<60).contains(seconds) else { return nil }
            return Double(minutes * 60 + seconds)
        }
        // `Double("inf")` and `Double("nan")` parse; neither is a stat.
        guard text.first.map({ $0.isNumber || $0 == "-" || $0 == "+" || $0 == "." }) == true,
              let number = Double(text), number.isFinite else { return nil }
        return number
    }
}

public extension ESPNSummaryResponse {
    /// Live stat lines for every player in this summary's box score.
    func playerStatLines(sport: SportType) -> [PlayerLiveStatLine] {
        PlayerLiveStatLine.lines(boxscore: boxscore, sport: sport)
    }

    /// Athlete ID → short name ("N. Jokic"), from the box score.
    var boxScoreAthleteNames: [String: String] {
        var names: [String: String] = [:]
        for team in boxscore?.players ?? [] {
            for group in team.statistics ?? [] {
                for line in group.athletes ?? [] {
                    guard let athlete = line.athlete, let id = athlete.id, names[id] == nil,
                          let name = athlete.shortName ?? athlete.displayName.map(PlayerBoxScore.shortName(from:))
                    else { continue }
                    names[id] = name
                }
            }
        }
        return names
    }

    /// `allPlays` with participant names filled from the box score where ESPN left
    /// them out (basketball, baseball).
    var allPlaysWithNamedParticipants: [Play] {
        let plays = allPlays
        guard plays.contains(where: { $0.participants != nil }) else { return plays }
        let names = boxScoreAthleteNames
        guard !names.isEmpty else { return plays }
        return plays.map { $0.namingParticipants(names) }
    }
}
