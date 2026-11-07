//
//  GolfLeaderboard.swift
//  SportsCalModel
//
//  Reading a golfer's line off ESPN's scoreboard (which rounds are finished, where the
//  current one stands, the next tee time) and the leaderboard facts every golf view
//  shares: tied positions, the round in play, a suspension.
//
//  ESPN's per-round linescore carries the strokes taken so far, finished or not: a
//  player through 9 on Friday reads `value: 34`. Counting that as a round is what put
//  "34 (−38)" pills and short totals on the board, so a round only counts once all 18
//  holes are in (or, with no hole data, once the tournament has moved past it).
//

import Foundation

/// One golfer's rounds, split into finished ones and the one being played.
struct GolfRoundReading {
    /// Finished rounds, in order.
    let completed: [Linescore]
    /// The round being played right now, if any.
    let inProgress: Linescore?
    /// To-par for today's round ("-3").
    let today: String?
    /// "14", "8*" (started on the back nine), "F", or nil before the round starts.
    let thru: String?
    /// The next tee time, when the round hasn't started.
    let teeTime: GolfTeeTime?

    init(linescores: [Linescore], currentPeriod: Int, eventCompleted: Bool) {
        let rounds = linescores
            .filter { ($0.period ?? 0) > 0 && ($0.period ?? 0) < 5 } // 5+ is a playoff
            .sorted { ($0.period ?? 0) < ($1.period ?? 0) }

        func isComplete(_ round: Linescore) -> Bool {
            guard round.value != nil else { return false }
            if let holes = round.linescores, !holes.isEmpty { return holes.count >= 18 }
            return (round.period ?? 0) < currentPeriod || eventCompleted
        }

        let completed = rounds.filter(isComplete)
        let inProgress = rounds.first { $0.value != nil && !isComplete($0) }
        self.completed = completed
        self.inProgress = inProgress

        if let inProgress {
            today = inProgress.displayValue
            let holes = inProgress.linescores ?? []
            let backNineStart = holes.min(by: { ($0.period ?? 0) < ($1.period ?? 0) })?.period == 10
            thru = holes.isEmpty ? nil : "\(holes.count)\(backNineStart ? "*" : "")"
        } else if let last = completed.last, (last.period ?? 0) == currentPeriod {
            today = last.displayValue
            thru = "F"
        } else {
            today = nil
            thru = nil
        }

        // A tee time only matters for a round that hasn't started.
        if inProgress == nil {
            teeTime = rounds
                .filter { $0.value == nil }
                .lazy
                .compactMap { GolfTeeTime(round: $0) }
                .first
        } else {
            teeTime = nil
        }
    }
}

/// A tee time from a round's stats, which ESPN writes as "Thu Nov 05 13:49:00 PST 2026".
struct GolfTeeTime {
    let date: Date
    let timeZone: TimeZone?

    private static let posix = Locale(identifier: "en_US_POSIX")

    nonisolated(unsafe) private static let parser: DateFormatter = {
        let df = DateFormatter()
        df.locale = posix
        df.dateFormat = "EEE MMM dd HH:mm:ss zzz yyyy"
        return df
    }()

    nonisolated(unsafe) private static let iso = ISO8601DateFormatter()

    init?(round: Linescore) {
        let candidates = round.statistics?.categories?.flatMap { $0.stats ?? [] }.compactMap(\.displayValue) ?? []
        guard let parsed = candidates.lazy.compactMap({ GolfTeeTime(text: $0) }).first else { return nil }
        self = parsed
    }

    init?(text: String) {
        if let date = DateParsers.parse(text) {
            self.date = date
            self.timeZone = nil
            return
        }
        guard text.count > 20, let date = Self.parser.date(from: text) else { return nil }
        self.date = date
        let parts = text.split(separator: " ")
        self.timeZone = parts.count >= 5 ? TimeZone(abbreviation: String(parts[4])) : nil
    }

    var isoString: String { Self.iso.string(from: date) }

    /// "1:49 PM" in the course's time zone, for builds that show `teeTime` as is.
    var displayString: String {
        let df = DateFormatter()
        df.locale = Self.posix
        df.timeZone = timeZone ?? TimeZone(identifier: "America/New_York")
        df.dateFormat = "h:mm a"
        return df.string(from: date)
    }
}

// MARK: - Shared leaderboard reading

public extension Array where Element == LeaderboardEntry {
    /// Position labels in board order, with ties shown the way golf shows them: "1",
    /// "T3", "T3", "5". Players on the same score share the first position among them;
    /// anyone without a numeric to-par (CUT, WD, DQ) reads as that status instead.
    func golfPositionLabels() -> [String] {
        var labels: [String] = []
        labels.reserveCapacity(count)
        var index = 0
        while index < count {
            let entry = self[index]
            guard GolfScore.toPar(entry.score) != nil else {
                let status = entry.score.uppercased()
                labels.append(["CUT", "WD", "DQ", "MDF", "DNS"].contains(status) ? status : (entry.position > 0 ? "\(entry.position)" : "–"))
                index += 1
                continue
            }
            var end = index + 1
            while end < count, self[end].score == entry.score { end += 1 }
            let position = entry.position > 0 ? entry.position : index + 1
            let label = end - index > 1 ? "T\(position)" : "\(position)"
            labels.append(contentsOf: Array<String>(repeating: label, count: end - index))
            index = end
        }
        return labels
    }

    /// Position label per player name — for views that look players up by name.
    func golfPositionLabelsByName() -> [String: String] {
        var result: [String: String] = [:]
        for (entry, label) in zip(self, golfPositionLabels()) where result[entry.name] == nil {
            result[entry.name] = label
        }
        return result
    }
}

public enum GolfScore {
    /// "-12" → -12, "+3" → 3, "E" → 0. Nil for CUT/WD/"--".
    public static func toPar(_ text: String?) -> Int? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.uppercased() == "E" { return 0 }
        return Int(text.replacingOccurrences(of: "+", with: ""))
    }

    /// -3 → "-3", 0 → "E", 2 → "+2".
    public static func format(toPar value: Int) -> String {
        value == 0 ? "E" : (value > 0 ? "+\(value)" : "\(value)")
    }
}

public extension LeaderboardEntry {
    /// The next tee time, when ESPN published one.
    var teeTimeStart: Date? {
        teeTimeDate.flatMap(DateParsers.parse)
    }

    /// On the course right now: a round under way and not yet finished.
    var isOnCourse: Bool {
        guard let thruHole, !thruHole.isEmpty else { return false }
        return thruHole != "F" && thruHole != "-" && today != nil
    }
}

public extension Game {
    /// The round being played (or last played), from ESPN's "Round 2 - In Progress".
    var golfCurrentRound: Int? {
        guard let progress = strProgress?.lowercased(),
              let range = progress.range(of: #"round\s*(\d)"#, options: .regularExpression) else { return nil }
        return Int(progress[range].filter(\.isNumber))
    }

    /// Rounds the tournament is scheduled for: ESPN's count when the leaderboard feed
    /// supplied it, else 3 for LIV and 4 everywhere else (never fewer than were played).
    var golfScheduledRounds: Int {
        let played = (leaderboardEntries ?? []).map { $0.rounds.count + ($0.isOnCourse ? 1 : 0) }.max() ?? 0
        let scheduled = golfCourseInfo?.numberOfRounds ?? (golfTour == .livGolf ? 3 : 4)
        return Swift.max(scheduled, played, golfCurrentRound ?? 0)
    }

    /// "Suspended" / "Delayed" while play is stopped (weather, darkness), else nil.
    var golfStoppageText: String? {
        guard let progress = strProgress, !hasFinishedGolf else { return nil }
        let lower = progress.lowercased()
        for marker in ["suspended", "delayed", "delay", "postponed"] where lower.contains(marker) {
            return progress
        }
        return nil
    }

    private var hasFinishedGolf: Bool {
        isCompleted == true || (strProgress?.lowercased().hasPrefix("final") ?? false)
    }
}
