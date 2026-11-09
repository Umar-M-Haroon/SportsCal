//
//  GolfAlerts.swift
//  SportsCalModel
//
//  Alerts for followed golfers: teeing off, taking the lead, finishing a round, winning.
//  The server's golf alert job reads each live tournament's whole field every minute and
//  hands it to `GolfAlertDetector` with what it saw last time; the detector returns the
//  alerts that are new since then. Delivery (who gets which alert) is the job's.
//
//  Players are matched by name, as the leaderboard spells them, which is also how the
//  app stores followed players. `GolfAlertRegistration` is what the app posts to
//  `/notifications/golf`.
//

import Foundation

// MARK: - Alert kinds

public enum GolfAlertKind: String, Codable, CaseIterable, Hashable, Sendable {
    case teeOff
    case lead
    case finish

    /// For settings toggles.
    public var title: String {
        switch self {
        case .teeOff: return "Teeing off"
        case .lead: return "Taking the lead"
        case .finish: return "Finishing a round"
        }
    }
}

public struct GolfAlert: Equatable, Sendable {
    /// Stable per tournament, player and moment, so a device never gets it twice.
    public var id: String
    public var kind: GolfAlertKind
    /// The followed player it's about, as the leaderboard spells the name.
    public var player: String
    public var title: String
    public var body: String

    public init(id: String, kind: GolfAlertKind, player: String, title: String, body: String) {
        self.id = id
        self.kind = kind
        self.player = player
        self.title = title
        self.body = body
    }
}

// MARK: - Registration

/// What the app registers: its push token, the followed golfers (by leaderboard name),
/// and which kinds of alert.
public struct GolfAlertRegistration: Codable, Equatable, Sendable {
    public var token: String
    public var players: [String]
    public var kinds: [GolfAlertKind]

    public init(token: String, players: [String], kinds: [GolfAlertKind]) {
        self.token = token
        self.players = players
        self.kinds = kinds
    }
}

// MARK: - Detection

/// What the detector saw last time it looked at a tournament.
public struct GolfAlertState: Codable, Equatable, Sendable {
    public struct Player: Codable, Equatable, Sendable {
        /// Rounds this player has been seen on the course in, or finishing.
        public var startedRounds: Set<Int>
        public var finishedRounds: Set<Int>
        /// Rounds in which a lead alert has gone, so a lead changing hands back and
        /// forth announces once a round.
        public var ledRounds: Set<Int>

        public init(startedRounds: Set<Int> = [], finishedRounds: Set<Int> = [], ledRounds: Set<Int> = []) {
            self.startedRounds = startedRounds
            self.finishedRounds = finishedRounds
            self.ledRounds = ledRounds
        }
    }

    public var players: [String: Player]
    public var winnerAnnounced: Bool

    public init(players: [String: Player] = [:], winnerAnnounced: Bool = false) {
        self.players = players
        self.winnerAnnounced = winnerAnnounced
    }
}

public enum GolfAlertDetector {
    /// A tee-off alert goes only while the player is this early in the round, so a
    /// player first seen mid-round (a restart, a late follow) isn't announced.
    static let teeOffHoleLimit = 4

    /// The alerts that are new in `tournament` for `players` since `previous`, and the
    /// state to keep.
    ///
    /// A player with no previous state (the first look at the tournament, a server
    /// restart, a newly followed player) has whatever is already on the board taken as
    /// seen rather than announced, so nobody gets a burst of stale alerts.
    ///
    /// - Parameters:
    ///   - tournament: The tournament with its whole field (`/golf/tournament`).
    ///   - players: Followed players' names, as the leaderboard spells them.
    ///   - previous: The state returned last time, or nil on the first look.
    public static func detect(
        _ tournament: Game,
        players: Set<String>,
        previous: GolfAlertState?
    ) -> (alerts: [GolfAlert], state: GolfAlertState) {
        let board = tournament.resolvedLeaderboard
        let labels = board.golfPositionLabelsByName()
        let eventID = tournament.idEvent ?? tournament.id
        let isFinal = tournament.isCompleted == true || (tournament.strProgress?.lowercased().hasPrefix("final") ?? false)
        let currentRound = tournament.golfCurrentRound

        var state = previous ?? GolfAlertState()
        var alerts: [GolfAlert] = []

        for entry in board where players.contains(entry.name) {
            let reading = Reading(entry: entry, label: labels[entry.name], tournamentRound: currentRound)
            guard var seen = state.players[entry.name] else {
                // First sight of this player: remember, don't announce.
                state.players[entry.name] = reading.seenAsIs
                if isFinal { state.winnerAnnounced = true }
                continue
            }

            if let round = reading.onCourseRound, !seen.startedRounds.contains(round) {
                seen.startedRounds.insert(round)
                if let holes = reading.holesPlayed, holes <= teeOffHoleLimit, !isFinal {
                    alerts.append(teeOffAlert(entry, round: round, label: reading.label, tournament: tournament, eventID: eventID))
                }
            }

            if let round = reading.finishedRound, !seen.finishedRounds.contains(round) {
                seen.finishedRounds.insert(round)
                seen.startedRounds.insert(round)
                alerts.append(finishAlert(entry, round: round, label: reading.label, tournament: tournament, eventID: eventID))
            }

            if reading.label == "1", !isFinal, let round = reading.onCourseRound ?? reading.finishedRound ?? currentRound,
               !seen.ledRounds.contains(round) {
                seen.ledRounds.insert(round)
                alerts.append(leadAlert(entry, round: round, tournament: tournament, eventID: eventID))
            }

            if isFinal, !state.winnerAnnounced, reading.label == "1" {
                alerts.append(GolfAlert(
                    id: "\(eventID)-\(entry.name)-win", kind: .finish, player: entry.name,
                    title: "🏆 \(entry.name) wins",
                    body: "\(tournament.strHomeTeam) at \(display(entry.score))"
                ))
            }
            state.players[entry.name] = seen
        }
        if isFinal { state.winnerAnnounced = true }
        return (alerts, state)
    }

    // MARK: Reading a row

    /// What one leaderboard row says about the player's round.
    struct Reading {
        let label: String?
        /// The round under way, when on the course.
        let onCourseRound: Int?
        /// The round just finished ("F"), while it's still the current round.
        let finishedRound: Int?
        /// Holes played in the round under way.
        let holesPlayed: Int?

        init(entry: LeaderboardEntry, label: String?, tournamentRound: Int?) {
            self.label = label
            let thru = entry.thruHole ?? ""
            if entry.isOnCourse {
                onCourseRound = entry.rounds.count + 1
                finishedRound = nil
                holesPlayed = Int(thru.prefix { $0.isNumber })
            } else if thru == "F", !entry.rounds.isEmpty {
                onCourseRound = nil
                finishedRound = entry.rounds.count
                holesPlayed = nil
            } else {
                onCourseRound = nil
                finishedRound = nil
                holesPlayed = nil
            }
        }

        /// Everything on the board now, taken as already seen.
        var seenAsIs: GolfAlertState.Player {
            var player = GolfAlertState.Player()
            if let round = onCourseRound { player.startedRounds.insert(round) }
            if let round = finishedRound {
                player.startedRounds.insert(round)
                player.finishedRounds.insert(round)
            }
            if label == "1", let round = onCourseRound ?? finishedRound { player.ledRounds.insert(round) }
            return player
        }
    }

    // MARK: Builders

    private static func teeOffAlert(_ entry: LeaderboardEntry, round: Int, label: String?, tournament: Game, eventID: String) -> GolfAlert {
        let standing = round > 1 ? " · \(display(entry.score))\(label.map { ", \($0)" } ?? "")" : ""
        return GolfAlert(
            id: "\(eventID)-\(entry.name)-r\(round)-tee", kind: .teeOff, player: entry.name,
            title: "⛳️ \(entry.name) tees off",
            body: "Round \(round) of \(tournament.strHomeTeam)\(standing)"
        )
    }

    private static func leadAlert(_ entry: LeaderboardEntry, round: Int, tournament: Game, eventID: String) -> GolfAlert {
        let thru = entry.isOnCourse ? " thru \(entry.thruHole ?? "")" : ""
        return GolfAlert(
            id: "\(eventID)-\(entry.name)-r\(round)-lead", kind: .lead, player: entry.name,
            title: "\(entry.name) takes the lead",
            body: "\(display(entry.score))\(thru) · \(tournament.strHomeTeam), round \(round)"
        )
    }

    private static func finishAlert(_ entry: LeaderboardEntry, round: Int, label: String?, tournament: Game, eventID: String) -> GolfAlert {
        let parts = [entry.today.map { "\(display($0)) today" }, label, tournament.strHomeTeam]
        return GolfAlert(
            id: "\(eventID)-\(entry.name)-r\(round)-finish", kind: .finish, player: entry.name,
            title: "\(entry.name) finishes round \(round) at \(display(entry.score))",
            body: parts.compactMap { $0 }.joined(separator: " · ")
        )
    }

    /// "-12" → "−12" (a real minus sign reads better in a notification).
    static func display(_ score: String) -> String {
        score.hasPrefix("-") ? "−" + score.dropFirst() : score
    }
}
