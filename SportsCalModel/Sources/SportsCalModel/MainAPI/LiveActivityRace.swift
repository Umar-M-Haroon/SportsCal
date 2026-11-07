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
        /// Golf: the position as shown ("T3"), and where the player is ("Thru 14", "F").
        public var label: String?
        public var detail: String?

        public init(position: Int, code: String, gap: String? = nil, teamColor: String? = nil, label: String? = nil, detail: String? = nil) {
            self.position = position
            self.code = code
            self.gap = gap
            self.teamColor = teamColor
            self.label = label
            self.detail = detail
        }
    }

    /// Short session label ("Race", "Sprint", "Quali", "FP2"; "Round 2" for golf).
    public var session: String
    public var leaders: [Driver]
    /// "golf" for a golf leaderboard; nil for racing (every activity before golf had one).
    public var sport: String?
    /// Golf: the player the activity follows, when they aren't already in `leaders`.
    public var following: Driver?

    public init(session: String, leaders: [Driver], sport: String? = nil, following: Driver? = nil) {
        self.session = session
        self.leaders = leaders
        self.sport = sport
        self.following = following
    }

    public var isGolf: Bool { sport == "golf" }

    /// Golf Live Activity content: the round, the top three (with ties) and, when the
    /// activity follows a player outside them, that player's line. `following` is the
    /// activity's `awayTeam` attribute — a player name, or the tour name when it
    /// follows the tournament as a whole.
    public init?(golf game: Game, following: String?) {
        let entries = game.leaderboardEntries ?? []
        guard game.golfTour != nil, !entries.isEmpty else { return nil }
        let labels = entries.golfPositionLabels()
        func driver(_ index: Int) -> Driver {
            let entry = entries[index]
            let detail: String?
            if entry.isOnCourse, let thru = entry.thruHole {
                detail = "Thru \(thru)"
            } else if entry.thruHole == "F" {
                detail = "F"
            } else {
                detail = nil
            }
            return Driver(position: entry.position, code: Self.golfName(entry.name),
                          gap: entry.score, label: labels[index], detail: detail)
        }
        let top = (0..<Swift.min(Self.leaderCount, entries.count)).map(driver)
        self.session = game.golfCurrentRound.map { "Round \($0)" } ?? "Leaderboard"
        self.leaders = top
        self.sport = "golf"
        if let following, let index = entries.firstIndex(where: { $0.name == following }), index >= Self.leaderCount {
            self.following = driver(index)
        } else {
            self.following = nil
        }
    }

    /// "Scottie Scheffler" → "S. Scheffler".
    static func golfName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        guard parts.count >= 2, let initial = parts.first?.first else { return name }
        return "\(initial). \(parts.dropFirst().joined(separator: " "))"
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
        // Endurance cars carry a crew ("Cameron / Nasr / Tandy"), so initials of the
        // first driver read as nonsense ("CAM"); the car number is what fans follow.
        let usesCarNumber = game.isEnduranceRacing
        self.leaders = top.map { entry in
            Driver(
                position: entry.position,
                code: Self.code(for: entry, usesCarNumber: usesCarNumber, standings: standings),
                gap: entry.position == 1 ? nil : Self.shortGap(entry.gap),
                teamColor: entry.stockCar.flatMap { NASCARVocabulary.manufacturerColorHex($0.manufacturer) }
                    ?? entry.constructor.flatMap { standings?.teamColorHex(for: $0) }
            )
        }
    }

    /// Short series code for the Dynamic Island slots, where a race has no team
    /// abbreviation ("F1", "CUP", "INDY", "IMSA", "WEC"). Shared by the app's own
    /// starts and the server's push-to-start so both label the activity the same.
    public static func seriesCode(for game: Game) -> String {
        switch game.racingSeries {
        case .nascarCup: "CUP"
        case .indycar: "INDY"
        case .imsa: "IMSA"
        case .wec: "WEC"
        default: "F1"
        }
    }

    static func code(for entry: LeaderboardEntry, usesCarNumber: Bool, standings: F1Standings?) -> String {
        if usesCarNumber, let number = entry.stockCar?.carNumber, !number.isEmpty {
            return "#\(number)"
        }
        return standings?.driverCode(for: entry.name) ?? fallbackCode(entry.name)
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
