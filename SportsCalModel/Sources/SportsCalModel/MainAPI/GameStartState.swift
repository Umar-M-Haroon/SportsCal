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

    /// The score to keep for a game in `status`. ESPN reports "0" for both sides before
    /// kickoff, which rows rendered as a real 0–0, so a not-started game keeps none.
    static func scoreIfStarted(_ score: String?, status: String?) -> String? {
        isNotStarted(status: status) ? nil : score
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

    internal static func isMidnightEastern(_ date: Date) -> Bool {
        guard let eastern = TimeZone(identifier: "America/New_York") else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return parts.hour == 0 && parts.minute == 0 && (parts.second ?? 0) == 0
    }
}
