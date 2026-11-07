//
//  PlayGrouping.swift
//  SportsCalModel
//
//  Shapes a flat play-by-play list for display. Baseball arrives pitch by pitch (a
//  nine-inning game is ~600 rows, many of them blank start/end markers), so it folds
//  into half-innings of plate appearances with their pitches tucked under each one.
//  Football arrives as one list split back into drives by `DriveSummary.firstPlayID`.
//

import Foundation

// MARK: - Baseball

/// One plate appearance (or a pitching change / steal between them) and the pitches
/// that led to it.
public struct BaseballAtBat: Equatable, Hashable, Identifiable {
    public var result: Play
    /// Oldest first. Empty for pitching changes and mid-at-bat events.
    public var pitches: [Play]

    public var id: String { result.id }

    public init(result: Play, pitches: [Play] = []) {
        self.result = result
        self.pitches = pitches
    }
}

/// The top or bottom of an inning.
public struct BaseballHalfInning: Equatable, Hashable, Identifiable {
    public var inning: Int
    public var isTop: Bool
    /// Oldest first.
    public var atBats: [BaseballAtBat]

    public var id: String { "\(inning)-\(isTop ? "top" : "bottom")" }

    public init(inning: Int, isTop: Bool, atBats: [BaseballAtBat]) {
        self.inning = inning
        self.isTop = isTop
        self.atBats = atBats
    }
}

public extension Play {
    /// Whether ESPN tagged this row with its baseball kind. Payloads archived before
    /// the field was carried have none.
    var hasBaseballSummaryType: Bool { summaryType != nil }

    /// A row worth listing in baseball: an at-bat's result ("Judge homered to left"),
    /// a pitching change, or a mid-at-bat event (stolen base, wild pitch, balk). Not
    /// pitches, "now batting" rows, inning starts or the blank end-of markers.
    var isBaseballResult: Bool {
        switch summaryType {
        case "N", "S", "C":
            return true
        case nil:
            guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            return !(type?.text?.hasPrefix("End") ?? false)
        default:
            return false
        }
    }

    /// Baseball: a single pitch.
    var isPitch: Bool { summaryType == "P" }

    /// Baseball: "Top" → true, "Bottom" → false; nil for Mid/End markers or no half.
    var isTopHalf: Bool? {
        switch period?.type?.lowercased() {
        case "top": return true
        case "bottom", "bot": return false
        default: return nil
        }
    }
}

public extension Array where Element == Play {
    /// Baseball rows grouped by half-inning, oldest first, keeping only results (see
    /// ``Play/isBaseballResult``) with each at-bat's pitches folded under it.
    ///
    /// Payloads from before the server carried `summaryType` can't be told apart row by
    /// row, so they keep every non-blank row, still split by half where ESPN said which.
    func baseballHalfInnings() -> [BaseballHalfInning] {
        let tagged = contains { $0.hasBaseballSummaryType }
        var pitchesByAtBat: [String: [Play]] = [:]
        if tagged {
            for play in self where play.isPitch {
                guard let atBat = play.atBatId else { continue }
                pitchesByAtBat[atBat, default: []].append(play)
            }
        }

        var halves: [BaseballHalfInning] = []
        for play in self {
            let keep = tagged
                ? play.isBaseballResult
                : !(play.text?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
            guard keep, let inning = play.period?.number else { continue }
            let isTop = play.isTopHalf ?? halves.last?.isTop ?? true
            // A pitching change shares its at-bat ID with the batter who follows; the
            // pitches belong to that batter's result.
            let pitches = (play.summaryType == "C") ? [] : play.atBatId.flatMap { pitchesByAtBat[$0] } ?? []
            let atBat = BaseballAtBat(result: play, pitches: pitches)
            if let last = halves.last, last.inning == inning, last.isTop == isTop {
                halves[halves.count - 1].atBats.append(atBat)
            } else {
                halves.append(BaseballHalfInning(inning: inning, isTop: isTop, atBats: [atBat]))
            }
        }
        return halves
    }

    /// How many rows the play-by-play actually lists — results only for baseball.
    func displayedPlayCount(isBaseball: Bool) -> Int {
        guard isBaseball else { return count }
        return baseballHalfInnings().reduce(0) { $0 + $1.atBats.count }
    }
}

// MARK: - Football

/// A run of plays under one drive header. `drive` is nil for plays before the first
/// known drive (or when the payload has no drive headers).
public struct PlayDriveGroup: Equatable, Hashable, Identifiable {
    public var drive: DriveSummary?
    /// Oldest first.
    public var plays: [Play]

    public var id: String { drive?.firstPlayID ?? plays.first?.id ?? "none" }

    public init(drive: DriveSummary?, plays: [Play]) {
        self.drive = drive
        self.plays = plays
    }
}

public extension Array where Element == Play {
    /// Splits plays (oldest first) at each drive's first play. Without drives, one
    /// group holds everything.
    func groupedIntoDrives(_ drives: [DriveSummary]?) -> [PlayDriveGroup] {
        let byFirstPlay = Dictionary((drives ?? []).map { ($0.firstPlayID, $0) }, uniquingKeysWith: { first, _ in first })
        var groups: [PlayDriveGroup] = []
        for play in self {
            if let drive = byFirstPlay[play.id] {
                groups.append(PlayDriveGroup(drive: drive, plays: [play]))
            } else if groups.isEmpty {
                groups.append(PlayDriveGroup(drive: nil, plays: [play]))
            } else {
                groups[groups.count - 1].plays.append(play)
            }
        }
        return groups
    }
}
