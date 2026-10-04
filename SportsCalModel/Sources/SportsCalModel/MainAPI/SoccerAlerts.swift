//
//  SoccerAlerts.swift
//  SportsCalModel
//
//  FotMob-style match alerts for followed soccer teams. The server's alert job
//  fetches each followed match's `SoccerMatchDetail` every minute and hands it to
//  `SoccerAlertDetector` with what it saw last time; the detector returns the
//  alerts that are new since then. Delivery (who gets which alert) is the job's.
//
//  `SoccerAlertRegistration` is what the app posts to `/notifications/soccer`.
//

import Foundation

// MARK: - Alert kinds

public enum SoccerAlertKind: String, Codable, CaseIterable, Hashable, Sendable {
    case lineups
    case goal
    case redCard
    case penaltyMissed
    case goalDisallowed
    case halfTime
    case fullTime

    /// For settings toggles.
    public var title: String {
        switch self {
        case .lineups: return "Lineups announced"
        case .goal: return "Goals"
        case .redCard: return "Red cards"
        case .penaltyMissed: return "Missed penalties"
        case .goalDisallowed: return "Goals ruled out by VAR"
        case .halfTime: return "Half-time score"
        case .fullTime: return "Full-time score"
        }
    }
}

public struct SoccerAlert: Equatable, Sendable {
    /// Stable per match and moment, so a device is never sent the same alert twice.
    public var id: String
    public var kind: SoccerAlertKind
    public var title: String
    public var body: String

    public init(id: String, kind: SoccerAlertKind, title: String, body: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
    }
}

// MARK: - Registration

/// What the app registers: its push token, the teams it wants alerts for (by the
/// names its games carry), and which kinds of alert.
public struct SoccerAlertRegistration: Codable, Equatable, Sendable {
    public var token: String
    public var teams: [String]
    public var kinds: [SoccerAlertKind]

    public init(token: String, teams: [String], kinds: [SoccerAlertKind]) {
        self.token = token
        self.teams = teams
        self.kinds = kinds
    }
}

// MARK: - Detection

/// What the detector saw last time it looked at a match.
public struct SoccerAlertState: Codable, Equatable, Sendable {
    /// Key-event and commentary ids already accounted for, alerted or not.
    public var seenIDs: Set<String>
    public var lineupsAnnounced: Bool
    public var halfTimeAnnounced: Bool
    public var fullTimeAnnounced: Bool

    public init(seenIDs: Set<String> = [], lineupsAnnounced: Bool = false,
                halfTimeAnnounced: Bool = false, fullTimeAnnounced: Bool = false) {
        self.seenIDs = seenIDs
        self.lineupsAnnounced = lineupsAnnounced
        self.halfTimeAnnounced = halfTimeAnnounced
        self.fullTimeAnnounced = fullTimeAnnounced
    }
}

public enum SoccerAlertDetector {
    /// The alerts that are new in `match` since `previous`, and the state to keep.
    ///
    /// With no previous state (the first look at a match, or after a server restart
    /// mid-match) everything already in the match is taken as seen rather than
    /// announced, so nobody gets a burst of stale goals. The one exception is
    /// lineups before kickoff: announcing them is the point of looking early.
    public static func detect(
        _ match: SoccerMatchDetail,
        previous: SoccerAlertState?
    ) -> (alerts: [SoccerAlert], state: SoccerAlertState) {
        let status = match.status
        let lineupsReady = match.home.starters.count == 11 && match.away.starters.count == 11
        let currentIDs = Set(match.events.map(\.id)).union(disallowedGoals(match).map(\.id))

        guard let previous else {
            let isPreMatch = status?.state == "pre"
            let pastHalfTime = status.map { $0.isHalfTime || $0.isFinished || secondHalfStarted(match) } ?? false
            let state = SoccerAlertState(
                seenIDs: currentIDs,
                lineupsAnnounced: lineupsReady,
                halfTimeAnnounced: pastHalfTime,
                fullTimeAnnounced: status?.isFinished ?? false
            )
            let alerts = lineupsReady && isPreMatch ? [lineupsAlert(match)] : []
            return (alerts, state)
        }

        var state = previous
        var alerts: [SoccerAlert] = []

        if lineupsReady, !state.lineupsAnnounced {
            state.lineupsAnnounced = true
            // Lineups that only appear once the match is under way aren't news.
            if status?.state == "pre" { alerts.append(lineupsAlert(match)) }
        }

        for event in match.events where !state.seenIDs.contains(event.id) {
            state.seenIDs.insert(event.id)
            // Shootout kicks (period 5) aren't goals or missed penalties in the match;
            // the full-time alert carries the result.
            if (event.period ?? 1) >= 5 { continue }
            if let alert = eventAlert(event, match: match) { alerts.append(alert) }
        }

        for entry in disallowedGoals(match) where !state.seenIDs.contains(entry.id) {
            state.seenIDs.insert(entry.id)
            alerts.append(SoccerAlert(
                id: "\(match.eventID)-\(entry.id)", kind: .goalDisallowed,
                title: "❌ Goal ruled out — \(scoreLine(match))",
                body: [entry.clock, entry.text].compactMap { $0 }.joined(separator: " ")
            ))
        }

        if let status, status.isHalfTime, !state.halfTimeAnnounced {
            state.halfTimeAnnounced = true
            alerts.append(SoccerAlert(id: "\(match.eventID)-ht", kind: .halfTime,
                                      title: "Half-time", body: scoreLine(match)))
        }

        if let status, status.isFinished, !state.fullTimeAnnounced {
            state.fullTimeAnnounced = true
            state.halfTimeAnnounced = true
            alerts.append(SoccerAlert(id: "\(match.eventID)-ft", kind: .fullTime,
                                      title: "Full-time", body: scoreLine(match)))
        }

        return (alerts, state)
    }

    // MARK: Builders

    private static func lineupsAlert(_ match: SoccerMatchDetail) -> SoccerAlert {
        let formations = [match.home.formation, match.away.formation].compactMap { $0 }
        return SoccerAlert(
            id: "\(match.eventID)-lineups", kind: .lineups,
            title: "Lineups are out",
            body: "\(match.home.teamName) v \(match.away.teamName)"
                + (formations.count == 2 ? " · \(formations[0]) v \(formations[1])" : "")
                + ". Tap to see the starting XIs."
        )
    }

    private static func eventAlert(_ event: SoccerMatchEvent, match: SoccerMatchDetail) -> SoccerAlert? {
        let team = event.side.map { $0 == .home ? match.home.teamName : match.away.teamName }
        let player = event.playerNames.first
        let clock = event.clock.map { " \($0)" } ?? ""
        let id = "\(match.eventID)-\(event.id)"
        switch event.type {
        case .goal, .penaltyGoal, .ownGoal:
            let note = event.type == .penaltyGoal ? " (pen)" : event.type == .ownGoal ? " (OG)" : ""
            let assist = event.type == .goal && event.playerNames.count > 1 ? ", assist \(event.playerNames[1])" : ""
            return SoccerAlert(
                id: id, kind: .goal,
                title: "⚽️ Goal! \(scoreLine(match))",
                body: player.map { "\($0)\(note)\(clock)\(assist)" } ?? "\(team ?? "Goal")\(clock)"
            )
        case .redCard:
            return SoccerAlert(
                id: id, kind: .redCard,
                title: "🟥 Red card\(team.map { " — \($0)" } ?? "")",
                body: "\(player ?? "A player") is sent off\(clock). \(scoreLine(match))"
            )
        case .penaltyMissed:
            return SoccerAlert(
                id: id, kind: .penaltyMissed,
                title: "Penalty missed\(team.map { " — \($0)" } ?? "")",
                body: "\(player ?? "The taker") fails to score\(clock). \(scoreLine(match))"
            )
        case .yellowCard, .substitution, .other:
            return nil
        }
    }

    /// "Liverpool 1–0 Man City", from the latest score; just the teams before one exists.
    static func scoreLine(_ match: SoccerMatchDetail) -> String {
        guard let home = match.status?.homeScore, let away = match.status?.awayScore else {
            return "\(match.home.teamName) v \(match.away.teamName)"
        }
        return "\(match.home.teamName) \(home)–\(away) \(match.away.teamName)"
    }

    /// VAR reversals of a goal: ESPN posts "GOAL OVERTURNED BY VAR: …" (and never a
    /// goal row for it), or a "VAR Decision: No Goal …" line.
    static func disallowedGoals(_ match: SoccerMatchDetail) -> [SoccerCommentaryEntry] {
        var kept: [SoccerCommentaryEntry] = []
        for entry in match.commentary where entry.kind == .var {
            let text = entry.text.lowercased()
            guard text.contains("goal overturned") || text.contains("decision: no goal") else { continue }
            // ESPN posts both lines for one reversal, up to a couple of minutes
            // apart (AZ–Telstar: 55' and 57'); announce it once.
            if let last = kept.last, let a = minute(last.clock), let b = minute(entry.clock), abs(a - b) <= 3 {
                continue
            }
            kept.append(entry)
        }
        return kept.map { entry in
            var entry = entry
            entry.id = "var-\(entry.id)"
            return entry
        }
    }

    /// "45'+2'" → 45.
    private static func minute(_ clock: String?) -> Int? {
        clock.flatMap { Int($0.prefix { $0.isNumber }) }
    }

    private static func secondHalfStarted(_ match: SoccerMatchDetail) -> Bool {
        match.events.contains { ($0.period ?? 1) >= 2 }
    }
}
