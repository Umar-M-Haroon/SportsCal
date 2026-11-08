//
//  GameStartState.swift
//  SportsCalModel
//
//  Not-started games: no score, and maybe no kickoff time yet.
//

import Foundation

public extension Game {
    /// ESPN's `pre` and TheSportsDB's `NS` both mean the game hasn't started.
    static func isNotStarted(status: String?) -> Bool {
        guard let status else { return false }
        return status == "pre" || status == "NS"
    }

    /// The scores to keep for a game in `status`. ESPN reports "0" for both sides before
    /// kickoff, which rows rendered as a real 0–0, so a not-started game's 0–0 is dropped.
    /// Only that placeholder: TheSportsDB leaves some finished games at "NS" with their
    /// real result, and dropping every NS score erased those results for good once the
    /// server wrote the copy back.
    static func scoresIfStarted(home: String?, away: String?, status: String?) -> (home: String?, away: String?) {
        guard isNotStarted(status: status) else { return (home, away) }
        func isPlaceholder(_ score: String?) -> Bool {
            guard let score = score?.trimmingCharacters(in: .whitespaces), !score.isEmpty else { return true }
            return Int(score) == 0
        }
        return isPlaceholder(home) && isPlaceholder(away) ? (nil, nil) : (home, away)
    }

    /// The kickoff time isn't set yet: show "TBD" instead of a clock time.
    ///
    /// Servers that send `timeTBD` are authoritative. For older payloads, a college
    /// football game parked at exactly midnight Eastern is ESPN's TBD placeholder
    /// (`timeValid: false`, "11/14 - TBD") — no FBS game kicks off at 12:00 AM ET.
    var isTimeTBD: Bool {
        guard Game.isNotStarted(status: strStatus) || strStatus == nil else { return false }
        if timeTBD == true { return true }
        guard isCollegeFootball, let date = isoDate else { return false }
        return Game.isMidnightEastern(date)
    }

    /// Where a TBD game sits on the clock: noon Eastern on its day. The source parks it
    /// at midnight Eastern, which is the evening before anywhere west of New York, so
    /// rows, day grouping and the detail header put it on the wrong day. Noon Eastern is
    /// the same calendar day from Hawaii to New Zealand.
    static func tbdAnchorDate(_ placeholder: Date) -> Date {
        let calendar = easternCalendar
        let day = calendar.startOfDay(for: placeholder)
        return calendar.date(byAdding: .hour, value: 12, to: day) ?? placeholder
    }

    /// Gregorian in America/New_York, built once: `isTimeTBD` runs inside sort comparators.
    private static let easternCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }()

    internal static func isMidnightEastern(_ date: Date) -> Bool {
        let parts = easternCalendar.dateComponents([.hour, .minute, .second], from: date)
        return parts.hour == 0 && parts.minute == 0 && (parts.second ?? 0) == 0
    }
}
