//
//  LiveActivityRace.swift
//  SportsCalModel
//

import Foundation

/// F1 Live Activity content: the running session and the top three. Rides in the Live
/// Activity `ContentState` as an optional field (older activities and servers decode
/// fine without it). Built in one place so the app's foreground updates and the
/// server's APNS pushes always agree, keeping the state-diff dedup stable.
///
/// Deliberately small: APNS caps the payload at 4KB, and the full leaderboard that F1
/// games carry in `lastPlay` would blow past it on every push.
public struct LiveActivityRace: Codable, Hashable, Sendable {
    public struct Driver: Codable, Hashable, Sendable {
        public var position: Int
        /// Three-letter code ("NOR").
        public var code: String
        /// Gap to the leader as the feed writes it ("+1.204"); nil for the leader.
        public var gap: String?
        /// Team colour hex without "#".
        public var teamColor: String?

        public init(position: Int, code: String, gap: String? = nil, teamColor: String? = nil) {
            self.position = position
            self.code = code
            self.gap = gap
            self.teamColor = teamColor
        }
    }

    /// Short session label ("Race", "Sprint", "Quali", "FP2").
    public var session: String
    public var leaders: [Driver]

    public init(session: String, leaders: [Driver]) {
        self.session = session
        self.leaders = leaders
    }

    public static let leaderCount = 3

    /// From an F1 weekend: the live session if one is running, else the most recent
    /// finished one. Nil when there's nothing classified yet.
    public init?(game: Game, standings: F1Standings?) {
        let sessions = game.sessions ?? []
        let live = sessions.first { $0.status == "in" }
        let session = live ?? sessions.last { $0.status == "post" && !$0.leaderboard.isEmpty }
        let entries = session?.leaderboard ?? game.leaderboardEntries ?? []
        let top = entries.filter { $0.position > 0 }.sorted { $0.position < $1.position }.prefix(Self.leaderCount)
        // A session that just went green often has no timing yet: still a race state
        // (empty leaders), so push-to-start lands on the F1 layout, not a "0-0" score.
        guard !top.isEmpty || live != nil else { return nil }

        // Series with lap counts (NASCAR) show where the race is instead of the session.
        if let state = session?.raceState, session?.status == "in", state.isTimed {
            // Endurance races run to a clock: "4:12:30 left".
            self.session = state.timeRemainingLabel ?? session?.progress ?? "Race"
        } else if let state = session?.raceState, session?.status == "in", state.lap > 0, state.totalLaps > 0 {
            self.session = state.flag == .yellow ? "Caution L\(state.lap)" : state.lapLabel
        } else {
            self.session = session?.shortName ?? "Race"
        }
        self.leaders = top.map { entry in
            Driver(
                position: entry.position,
                code: standings?.driverCode(for: entry.name) ?? Self.fallbackCode(entry.name),
                gap: entry.position == 1 ? nil : Self.shortGap(entry.gap),
                teamColor: entry.stockCar.flatMap { NASCARVocabulary.manufacturerColorHex($0.manufacturer) }
                    ?? entry.constructor.flatMap { standings?.teamColorHex(for: $0) }
            )
        }
    }

    static func fallbackCode(_ name: String) -> String {
        let surname = name.split(separator: " ").last.map(String.init) ?? name
        return String(surname.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).prefix(3)).uppercased()
    }

    /// Keeps the lock screen tidy: "+1 Lap" and "+0.412" pass, odd status text is capped.
    static func shortGap(_ gap: String?) -> String? {
        guard let gap = gap?.trimmingCharacters(in: .whitespaces), !gap.isEmpty else { return nil }
        return String(gap.prefix(9))
    }
}
