//
//  StandingsTable.swift
//  SportsCalModel
//
//  How each sport orders and reads an ESPN standings group. The game detail, team
//  page, league hub and the standings widget all draw from this, so a table ranks the
//  same way everywhere: by win percentage in basketball and baseball, by points in
//  hockey, by seed in the NFL, by conference record in college, by ESPN's own rank
//  (else points and goal difference) in soccer. Rank numbers are positions in that
//  order, not indices into ESPN's array.
//

import Foundation

// MARK: - Reading stats

public extension Entry {
    /// The first stat called `name` (ESPN's `name`, e.g. "wins", "otLosses").
    func stat(_ name: String) -> Stat? {
        stats?.first { $0.name == name }
    }

    func statValue(_ name: String) -> Double? {
        stat(name)?.value
    }

    /// The stat as ESPN displays it (".813", "W7", "+12"), else its value as a whole number.
    func statText(_ name: String) -> String? {
        guard let stat = stat(name) else { return nil }
        if let display = stat.displayValue, !display.isEmpty { return display }
        return stat.value.map { "\(Int($0))" }
    }

    /// The playoff marker ESPN puts on a clinched or eliminated team: "x", "y", "z", "*",
    /// "e". Nil when there's none.
    var clinchMarker: String? {
        guard let marker = statText("clincher")?.trimmingCharacters(in: .whitespaces),
              !marker.isEmpty, marker != "-", marker != "0" else { return nil }
        return marker
    }

    /// "W3", "L1".
    var streak: String? {
        guard let streak = statText("streak"), !streak.isEmpty, streak != "-" else { return nil }
        return streak
    }

    /// Record against conference opponents ("6-2"), where ESPN sends one.
    var conferenceRecord: String? {
        let stat = stats?.first { $0.type == "vsconf" || $0.name == "vs. Conf." }
        let record = stat?.summary ?? stat?.displayValue
        guard let record, record.contains("-") else { return nil }
        return record
    }

    /// Goal difference for soccer; ESPN calls it `pointDifferential`.
    var goalDifference: Double? {
        statValue("pointDifferential") ?? statValue("goalDifference")
    }
}

// MARK: - Columns

/// One column of a standings table.
public enum StandingsColumn: String, CaseIterable, Sendable {
    case gamesPlayed, wins, losses, ties, draws, otLosses, winPercent, gamesBehind,
         points, goalDifference, conferenceRecord, streak

    /// Header text.
    public var title: String {
        switch self {
        case .gamesPlayed: return "GP"
        case .wins: return "W"
        case .losses: return "L"
        case .ties: return "T"
        case .draws: return "D"
        case .otLosses: return "OTL"
        case .winPercent: return "PCT"
        case .gamesBehind: return "GB"
        case .points: return "PTS"
        case .goalDifference: return "GD"
        case .conferenceRecord: return "CONF"
        case .streak: return "STRK"
        }
    }

    /// What VoiceOver reads for the column.
    public var spokenName: String {
        switch self {
        case .gamesPlayed: return "played"
        case .wins: return "wins"
        case .losses: return "losses"
        case .ties: return "ties"
        case .draws: return "draws"
        case .otLosses: return "overtime losses"
        case .winPercent: return "win percentage"
        case .gamesBehind: return "games behind"
        case .points: return "points"
        case .goalDifference: return "goal difference"
        case .conferenceRecord: return "conference record"
        case .streak: return "streak"
        }
    }

    /// Wider columns hold ".813", "12.5", "10-2" or "W10".
    public var isWide: Bool {
        switch self {
        case .winPercent, .gamesBehind, .conferenceRecord, .streak: return true
        default: return false
        }
    }

    /// The cell text for `entry`, or "-" when ESPN didn't send the stat.
    public func value(for entry: Entry) -> String {
        let text: String?
        switch self {
        case .gamesPlayed: text = entry.statText("gamesPlayed")
        case .wins: text = entry.statText("wins")
        case .losses: text = entry.statText("losses")
        case .ties, .draws: text = entry.statText("ties") ?? entry.statText("draws")
        case .otLosses: text = entry.statText("otLosses") ?? entry.statText("overtimeLosses")
        case .winPercent: text = entry.statText("winPercent")
        case .gamesBehind: text = entry.statText("gamesBehind")
        case .points: text = entry.statText("points")
        case .goalDifference:
            text = entry.goalDifference.map { $0 > 0 ? "+\(Int($0))" : "\(Int($0))" }
        case .conferenceRecord: text = entry.conferenceRecord
        case .streak: text = entry.streak
        }
        return text ?? "-"
    }
}

// MARK: - Style

/// How a league's standings are ordered and which columns they show.
public enum StandingsStyle: Sendable, Equatable {
    /// NBA, WNBA: win percentage, games behind.
    case basketball
    /// College basketball: conference tables in conference-record order.
    case collegeBasketball
    /// NHL: points, with overtime losses shown.
    case hockey
    /// NFL: playoff seed where ESPN gives one.
    case football
    /// College football: conference record.
    case collegeFootball
    /// MLB: win percentage, games behind.
    case baseball
    /// Every soccer league: ESPN rank, else points then goal difference.
    case soccer

    public init(league: Leagues) {
        switch league {
        case .nba, .wnba: self = .basketball
        case .ncaaMBBTournament: self = .collegeBasketball
        case .nhl: self = .hockey
        case .nfl: self = .football
        case .ncaaf: self = .collegeFootball
        case .mlb: self = .baseball
        default: self = league.isSoccer ? .soccer : .basketball
        }
    }

    public var isSoccer: Bool { self == .soccer }

    /// The stat columns for a group, after rank and team. Ties appear only when a team
    /// in the group has one; conference record only when ESPN sends it.
    public func columns(for entries: [Entry]) -> [StandingsColumn] {
        switch self {
        case .basketball, .baseball:
            return [.wins, .losses, .winPercent, .gamesBehind]
        case .collegeBasketball:
            let conference: [StandingsColumn] = Self.hasConferenceRecords(entries) ? [.conferenceRecord] : []
            return [.wins, .losses, .winPercent] + conference
        case .hockey:
            return [.gamesPlayed, .wins, .losses, .otLosses, .points]
        case .football, .collegeFootball:
            let hasTies = entries.contains { ($0.statValue("ties") ?? 0) > 0 }
            var columns: [StandingsColumn] = [.wins, .losses]
            if hasTies { columns.append(.ties) }
            columns.append(.winPercent)
            if self == .collegeFootball, Self.hasConferenceRecords(entries) { columns.append(.conferenceRecord) }
            return columns
        case .soccer:
            return [.gamesPlayed, .wins, .draws, .losses, .goalDifference, .points]
        }
    }

    /// An extra column shown only when there's room for it.
    public var optionalColumn: StandingsColumn? {
        self == .soccer ? nil : .streak
    }

    /// `entries` best first, each with its position in that order.
    ///
    /// - Parameters:
    ///   - entries: One group's standings entries, in ESPN's order.
    ///   - combined: The entries come from several groups merged into one list
    ///     (the widget's league-wide table). Seeds and conference records only order a
    ///     single group, so a combined list falls back to the overall record.
    public func ranked(_ entries: [Entry], combined: Bool = false) -> [RankedStandingsEntry] {
        let indexed = Array(entries.enumerated())
        let sorted: [(offset: Int, element: Entry)]
        switch self {
        case .basketball, .baseball:
            sorted = indexed.sorted { Self.byWinPercent($0, $1) }
        case .hockey:
            sorted = indexed.sorted { Self.byPoints($0, $1) }
        case .football:
            let seeded = !combined && entries.allSatisfy { ($0.statValue("playoffSeed") ?? 0) > 0 }
            sorted = seeded ? indexed.sorted { Self.bySeed($0, $1) } : indexed.sorted { Self.byWinPercent($0, $1) }
        case .collegeBasketball, .collegeFootball:
            if combined {
                sorted = indexed.sorted { Self.byWinPercent($0, $1) }
            } else if Self.hasConferenceRecords(entries) {
                sorted = indexed.sorted { Self.byConferenceRecord($0, $1) }
            } else {
                sorted = indexed
            }
        case .soccer:
            sorted = indexed.sorted { Self.bySoccerTable($0, $1) }
        }
        return sorted.enumerated().map { position, item in
            RankedStandingsEntry(rank: position + 1, entry: item.element)
        }
    }

    // MARK: Orderings
    //
    // Each falls back to ESPN's order (`offset`) last, so a league missing the stats it
    // sorts on keeps the order ESPN sent.

    private typealias Indexed = (offset: Int, element: Entry)

    private static func byWinPercent(_ a: Indexed, _ b: Indexed) -> Bool {
        let pctA = a.element.statValue("winPercent") ?? -1
        let pctB = b.element.statValue("winPercent") ?? -1
        if pctA != pctB { return pctA > pctB }
        let winsA = a.element.statValue("wins") ?? -1
        let winsB = b.element.statValue("wins") ?? -1
        if winsA != winsB { return winsA > winsB }
        return a.offset < b.offset
    }

    /// NHL: points, then fewer games played (games in hand), then regulation wins.
    private static func byPoints(_ a: Indexed, _ b: Indexed) -> Bool {
        let pointsA = a.element.statValue("points") ?? -1
        let pointsB = b.element.statValue("points") ?? -1
        if pointsA != pointsB { return pointsA > pointsB }
        let playedA = a.element.statValue("gamesPlayed") ?? 0
        let playedB = b.element.statValue("gamesPlayed") ?? 0
        if playedA != playedB { return playedA < playedB }
        let regA = a.element.statValue("regWins") ?? a.element.statValue("wins") ?? -1
        let regB = b.element.statValue("regWins") ?? b.element.statValue("wins") ?? -1
        if regA != regB { return regA > regB }
        return a.offset < b.offset
    }

    private static func bySeed(_ a: Indexed, _ b: Indexed) -> Bool {
        let seedA = a.element.statValue("playoffSeed") ?? .greatestFiniteMagnitude
        let seedB = b.element.statValue("playoffSeed") ?? .greatestFiniteMagnitude
        if seedA != seedB { return seedA < seedB }
        return a.offset < b.offset
    }

    private static func byConferenceRecord(_ a: Indexed, _ b: Indexed) -> Bool {
        let recA = a.element.conferenceRecord.flatMap(RecordPercentage.init)
        let recB = b.element.conferenceRecord.flatMap(RecordPercentage.init)
        let pctA = recA?.percentage ?? -1
        let pctB = recB?.percentage ?? -1
        if pctA != pctB { return pctA > pctB }
        let winsA = recA?.wins ?? -1
        let winsB = recB?.wins ?? -1
        if winsA != winsB { return winsA > winsB }
        return byWinPercent(a, b)
    }

    /// ESPN's rank when it sends one (it applies each league's tiebreakers); otherwise
    /// points, goal difference, goals scored.
    private static func bySoccerTable(_ a: Indexed, _ b: Indexed) -> Bool {
        let rankA = a.element.statValue("rank") ?? a.element.note?.rank.map(Double.init)
        let rankB = b.element.statValue("rank") ?? b.element.note?.rank.map(Double.init)
        if let rankA, let rankB, rankA > 0, rankB > 0, rankA != rankB { return rankA < rankB }
        let pointsA = a.element.statValue("points") ?? -1
        let pointsB = b.element.statValue("points") ?? -1
        if pointsA != pointsB { return pointsA > pointsB }
        let gdA = a.element.goalDifference ?? 0
        let gdB = b.element.goalDifference ?? 0
        if gdA != gdB { return gdA > gdB }
        let forA = a.element.statValue("pointsFor") ?? 0
        let forB = b.element.statValue("pointsFor") ?? 0
        if forA != forB { return forA > forB }
        return a.offset < b.offset
    }

    private static func hasConferenceRecords(_ entries: [Entry]) -> Bool {
        entries.contains { $0.conferenceRecord != nil }
    }
}

/// A standings row with its position in the sorted table.
public struct RankedStandingsEntry {
    public let rank: Int
    public let entry: Entry

    public init(rank: Int, entry: Entry) {
        self.rank = rank
        self.entry = entry
    }
}

/// "6-2" or "6-2-1" read as wins and a win percentage (ties count half).
private struct RecordPercentage {
    let wins: Double
    let percentage: Double

    init?(_ record: String) {
        let parts = record.split(separator: "-").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 2 else { return nil }
        let ties = parts.count > 2 ? parts[2] : 0
        let games = parts[0] + parts[1] + ties
        wins = parts[0]
        percentage = games > 0 ? (parts[0] + ties / 2) / games : 0
    }
}

// MARK: - Groups

public extension Standing {
    /// Each conference / division / table that has rows, in ESPN's order.
    var groups: [(name: String?, entries: [Entry])] {
        (standings.children ?? []).compactMap { child in
            guard let entries = child.standings?.entries, !entries.isEmpty else { return nil }
            return (child.name, entries)
        }
    }
}
