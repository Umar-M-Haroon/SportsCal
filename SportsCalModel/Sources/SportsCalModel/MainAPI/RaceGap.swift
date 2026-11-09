//
//  RaceGap.swift
//  SportsCalModel
//
//  One reading of a leaderboard row's `gap` string, shared by the gap ribbon and the
//  session tables so they never disagree about what a value means.
//

import Foundation

public enum RaceGap: Equatable, Hashable {
    /// P1: the feed's value is the total race time or the fastest lap.
    case leader
    /// Seconds behind P1.
    case time(Double)
    /// An absolute lap time sent where a gap belongs (sprint qualifying sends
    /// "+1:11.608" behind a "1:11.567" pole), with the gap it implies.
    case lapTime(Double, behind: Double)
    case laps(Int)
    /// Not running: "DNF", "DNS", "Retired".
    case out(String)
    /// No value in the feed.
    case missing

    /// Seconds behind the leader, when the row is on the timing scale.
    public var seconds: Double? {
        switch self {
        case .leader: 0
        case .time(let s), .lapTime(_, let s): s
        case .laps, .out, .missing: nil
        }
    }

    /// Feed formats: "+0.099", "+1:02.345", "+1 Lap", "+2 Laps", "DNF", "Retired".
    public static func parse(_ raw: String?) -> RaceGap {
        guard let cleaned = raw?.trimmingCharacters(in: .whitespaces), !cleaned.isEmpty, cleaned != "--" else {
            return .missing
        }
        if cleaned.lowercased().contains("lap") {
            let digits = cleaned.filter(\.isNumber)
            return .laps(Int(digits) ?? 1)
        }
        let numeric = cleaned.hasPrefix("+") ? String(cleaned.dropFirst()) : cleaned
        if let seconds = clockSeconds(numeric) {
            return .time(seconds)
        }
        return .out(cleaned)
    }

    /// Every row's gap, in the order given. A value at least half the leader's own
    /// time can't be a gap (no one is half a lap down in qualifying), so it's read as
    /// an absolute lap time and converted.
    public static func gaps(for entries: [LeaderboardEntry]) -> [RaceGap] {
        guard let leader = entries.min(by: { rank($0) < rank($1) }) else { return [] }
        let leaderTime: Double? = {
            if case .time(let t) = parse(leader.gap) { return t }
            return nil
        }()
        return entries.map { entry in
            if entry == leader { return .leader }
            let gap = parse(entry.gap)
            guard case .time(let value) = gap, let leaderTime, leaderTime > 0, value >= leaderTime * 0.5 else { return gap }
            return .lapTime(value, behind: max(value - leaderTime, 0))
        }
    }

    /// Unclassified rows (position 0) sort after the field.
    private static func rank(_ entry: LeaderboardEntry) -> Int {
        entry.position == 0 ? Int.max : entry.position
    }

    /// Parses "ss.sss", "m:ss.sss" or "h:mm:ss.sss" into seconds.
    public static func clockSeconds(_ string: String) -> Double? {
        let components = string.split(separator: ":")
        guard !components.isEmpty, components.count <= 3 else { return nil }
        var total = 0.0
        for component in components {
            guard let value = Double(component), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// "1:11.608" / "12.345" / "1:02:11.004".
    public static func clockString(_ seconds: Double) -> String {
        if seconds >= 3600 {
            let hours = Int(seconds) / 3600
            let rest = seconds - Double(hours * 3600)
            return String(format: "%d:%02d:%06.3f", hours, Int(rest) / 60, rest - Double(Int(rest) / 60 * 60))
        }
        if seconds >= 60 {
            let minutes = Int(seconds) / 60
            return String(format: "%d:%06.3f", minutes, seconds - Double(minutes * 60))
        }
        return String(format: "%.3f", seconds)
    }

    /// "+0.041" / "+1:02.345".
    public static func gapString(_ seconds: Double) -> String {
        "+" + clockString(seconds)
    }
}
