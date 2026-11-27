//
//  CustomAlertRules.swift
//  SportsCal
//
//  The pure side of custom live alerts ("Player Alerts" + "Game Alerts"): which
//  sports and situations the app offers, turning the alert builder's choices into
//  `AlertRule`s (with IDs that stay stable across edits), the game-situation rules
//  derived from Settings, and the free/Pro cap check. No UserDefaults or network
//  here, so it's unit-tested in `CustomAlertRulesTests`.
//
//  The vocabulary (play types, milestones, filters, limits) is SportsCalModel's
//  `CustomAlerts.swift`, shared with the server's `CustomAlertJob`.
//
//  Wording: milestone language only ("reaches 30 points", "hits a home run"),
//  never betting terms.
//

import Foundation
import SportsCalModel

// MARK: - Catalog

enum CustomAlertCatalog {
    /// Whether a player on a `league` game can get player alerts (NBA, MLB, NHL and
    /// soccer; NFL for fantasy-points milestones only; no WNBA or college).
    static func supportsPlayerAlerts(sport: SportType?, league: Leagues?) -> Bool {
        guard let sport, AlertRule.playerPlaySports.contains(sport) || offersFantasyMilestones(sport) else { return false }
        return AlertRule.isPlayerAlertLeague(league, sport: sport)
    }

    /// Sports whose only player alert is a fantasy-points milestone (NFL).
    static func offersFantasyMilestones(_ sport: SportType) -> Bool {
        FantasyScoring.supports(sport) && AlertMilestone.presets(for: sport).contains { $0.stat == AlertMilestone.fantasyPoints }
    }

    /// Sports offered in Game Alerts, in display order.
    static let situationSports: [SportType] = [.basketball, .nfl, .mlb, .hockey]
        .filter { AlertRule.situationSports.contains($0) }

    /// The `ClutchMoment` kinds each sport can raise, in display order.
    static func situations(for sport: SportType) -> [ClutchMoment.Kind] {
        switch sport {
        case .basketball: return [.crunchTime, .scoringRun, .favoriteFlipped]
        case .nfl: return [.redZone, .favoriteFlipped]
        case .mlb: return [.tyingRunAtPlate, .goAheadRunInScoringPosition, .basesLoaded, .favoriteFlipped]
        case .hockey: return [.finalMinutesOneGoal, .tiedLate, .goaliePulled, .suddenDeathOvertime, .shootout]
        case .soccer, .golf, .tennis, .racing, .cricket: return []
        }
    }

    static func title(_ kind: ClutchMoment.Kind) -> String {
        switch kind {
        case .crunchTime: return "Crunch time"
        case .scoringRun: return "Big run late"
        case .favoriteFlipped: return "Momentum swing"
        case .redZone: return "Red zone, late and close"
        case .tyingRunAtPlate: return "Tying run at the plate"
        case .goAheadRunInScoringPosition: return "Go-ahead run in scoring position"
        case .basesLoaded: return "Bases loaded late"
        case .finalMinutesOneGoal: return "One-goal game, final 2 minutes"
        case .tiedLate: return "Tied late"
        case .goaliePulled: return "Goalie pulled"
        case .suddenDeathOvertime: return "Sudden-death overtime"
        case .shootout: return "Shootout"
        }
    }

    /// One line under the toggle: when it fires.
    static func detail(_ kind: ClutchMoment.Kind) -> String {
        switch kind {
        case .crunchTime: return "One-possession game in the final 2 minutes"
        case .scoringRun: return "A 10-0 run in the 4th that makes it a game"
        case .favoriteFlipped: return "Late on, the team more likely to win changes"
        case .redZone: return "4th quarter, one-score game, offense inside the 20"
        case .tyingRunAtPlate: return "9th inning or later"
        case .goAheadRunInScoringPosition: return "Tied in the 9th or later"
        case .basesLoaded: return "7th inning or later, within 3 runs"
        case .finalMinutesOneGoal: return "3rd period, under 2 minutes left"
        case .tiedLate: return "Under 5 minutes left in the 3rd"
        case .goaliePulled: return "The trailing team goes for the extra attacker"
        case .suddenDeathOvertime: return "Next goal wins"
        case .shootout: return "Decided by penalty shots"
        }
    }

    /// "Notify me when Stephen Curry hits a 3-pointer, throws down a dunk or reaches 30 points".
    static func summary(of rules: [AlertRule], sport: SportType) -> String {
        var parts: [String] = []
        for rule in rules {
            switch rule.kind {
            case .playerPlay:
                parts += (rule.playTypes ?? []).map { $0.phrase(sport: sport) }
            case .playerMilestone:
                if let milestone = rule.milestone { parts.append("reaches \(milestone.description(sport: sport))") }
            case .gameSituation:
                break
            }
        }
        guard !parts.isEmpty else { return "No alerts yet" }
        if parts.count == 1 { return parts[0] }
        return parts.dropLast().joined(separator: ", ") + " or " + parts.last!
    }

    /// "4th quarter or later" for the final-period filter's label.
    static func finalPeriodLabel(sport: SportType) -> String {
        switch sport {
        case .basketball, .nfl: return "Only in the 4th quarter or overtime"
        case .hockey: return "Only in the 3rd period or overtime"
        case .mlb: return "Only in the 9th inning or later"
        case .soccer: return "Only in the second half"
        case .golf, .tennis, .racing, .cricket: return "Only late in the game"
        }
    }

    static func closeGameLabel(sport: SportType) -> String {
        switch sport {
        case .basketball, .nfl: return "Only when it's within 8 points"
        case .mlb: return "Only when it's within 2 runs"
        case .hockey, .soccer: return "Only when it's within a goal"
        case .golf, .tennis, .racing, .cricket: return "Only when it's close"
        }
    }
}

// MARK: - Player alert builder

/// What the alert builder sheet edits for one player: the plays and milestones to be
/// told about, plus the filters, which apply to all of them. Becomes at most one
/// `playerPlay` rule (every chosen play type) and one `playerMilestone` rule per
/// milestone.
struct PlayerAlertDraft: Equatable {
    var player: PlayerRef
    var playTypes: Set<AlertPlayType>
    var milestones: [AlertMilestone]
    var finalPeriodOnly: Bool
    var closeGameOnly: Bool
    /// The scoring `fantasyPoints` milestones count with. Starts as the one the saved
    /// rules carry; the sheet sets the user's current scoring.
    var fantasyScoring: FantasyScoring?

    /// The draft for `player` as `rules` (the install's player rules) have it.
    init(player: PlayerRef, rules: [AlertRule]) {
        self.player = player
        let mine = rules.filter { $0.athleteID == player.athleteID && $0.isPlayerRule }
        playTypes = Set(mine.filter { $0.kind == .playerPlay }.flatMap { $0.playTypes ?? [] })
            .filter { $0.sports.contains(player.sport) }
        var milestones: [AlertMilestone] = []
        for rule in mine where rule.kind == .playerMilestone {
            if let milestone = rule.milestone, !milestones.contains(milestone) { milestones.append(milestone) }
        }
        self.milestones = milestones
        fantasyScoring = mine.lazy.compactMap(\.resolvedFantasyScoring).first
        finalPeriodOnly = mine.first?.finalPeriodOnly ?? false
        closeGameOnly = mine.first?.closeGameOnly ?? false
    }

    var offersPlays: Bool { AlertRule.playerPlaySports.contains(player.sport) }
    var offersMilestones: Bool {
        AlertRule.milestoneSports.contains(player.sport) || CustomAlertCatalog.offersFantasyMilestones(player.sport)
    }

    /// Adds a milestone unless the same one is already there.
    mutating func addMilestone(_ milestone: AlertMilestone) {
        guard milestone.threshold > 0, !milestones.contains(milestone) else { return }
        milestones.append(milestone)
    }

    /// The rules this draft stands for. IDs are reused from `existing` where the same
    /// rule was there before (the play rule; a milestone with the same stat and
    /// number), so editing doesn't look like new rules to the server.
    func rules(existing: [AlertRule], makeID: () -> String = { UUID().uuidString }) -> [AlertRule] {
        let mine = existing.filter { $0.athleteID == player.athleteID }
        var out: [AlertRule] = []
        func rule(id: String, kind: AlertRule.Kind, playTypes: [AlertPlayType]? = nil, milestone: AlertMilestone? = nil) -> AlertRule {
            // A fantasy milestone names a preset by ID, or carries a custom / league scoring whole.
            let isFantasy = milestone?.stat == AlertMilestone.fantasyPoints
            let presetID = isFantasy ? fantasyScoring.flatMap { FantasyScoring.preset(id: $0.id)?.id } : nil
            return AlertRule(
                id: id, kind: kind, sport: player.sport,
                athleteID: player.athleteID, athleteName: player.name, teamID: player.teamID,
                playTypes: playTypes, milestone: milestone,
                fantasyScoringID: presetID,
                fantasyScoring: isFantasy && presetID == nil ? fantasyScoring : nil,
                finalPeriodOnly: finalPeriodOnly, closeGameOnly: closeGameOnly
            )
        }
        if offersPlays {
            let ordered = AlertPlayType.types(for: player.sport).filter(playTypes.contains)
            if !ordered.isEmpty {
                let id = mine.first { $0.kind == .playerPlay }?.id ?? makeID()
                out.append(rule(id: id, kind: .playerPlay, playTypes: ordered))
            }
        }
        if offersMilestones {
            var used = Set<String>()
            for milestone in milestones where milestone.threshold > 0 {
                let isFantasy = milestone.stat == AlertMilestone.fantasyPoints
                // NFL has only fantasy milestones; a fantasy one needs a scoring.
                if isFantasy ? fantasyScoring == nil : !AlertRule.milestoneSports.contains(player.sport) { continue }
                let reused = mine.first {
                    $0.kind == .playerMilestone && $0.milestone == milestone && !used.contains($0.id)
                }?.id
                let id = reused ?? makeID()
                used.insert(id)
                out.append(rule(id: id, kind: .playerMilestone, milestone: milestone))
            }
        }
        return out
    }
}

// MARK: - Game situations

/// The Game Alerts choices: which situations are on per sport, and whether a sport's
/// alerts cover the user's favorite teams (the default) or every game of its league.
struct SituationAlertPrefs: Codable, Equatable {
    /// Sport raw value → situation kind raw values that are on.
    var kinds: [String: [String]] = [:]
    /// Sport raw values set to every game of the league rather than favorite teams.
    var allGamesSports: [String] = []

    func isOn(_ kind: ClutchMoment.Kind, sport: SportType) -> Bool {
        kinds[sport.rawValue]?.contains(kind.rawValue) ?? false
    }

    mutating func set(_ kind: ClutchMoment.Kind, sport: SportType, on: Bool) {
        var list = kinds[sport.rawValue] ?? []
        list.removeAll { $0 == kind.rawValue }
        if on { list.append(kind.rawValue) }
        kinds[sport.rawValue] = list.isEmpty ? nil : list
    }

    func enabledKinds(sport: SportType) -> [ClutchMoment.Kind] {
        CustomAlertCatalog.situations(for: sport).filter { isOn($0, sport: sport) }
    }

    func coversAllGames(_ sport: SportType) -> Bool { allGamesSports.contains(sport.rawValue) }

    mutating func setCoversAllGames(_ sport: SportType, _ allGames: Bool) {
        allGamesSports.removeAll { $0 == sport.rawValue }
        if allGames { allGamesSports.append(sport.rawValue) }
    }

    var hasAny: Bool { kinds.values.contains { !$0.isEmpty } }
}

enum SituationAlertRules {
    private static let prefix = "sit"

    /// Stable, so a re-sync replaces rather than adds: `sit-basketball-crunchTime-134862`.
    static func ruleID(sport: SportType, kind: ClutchMoment.Kind, teamID: String?) -> String {
        "\(prefix)-\(sport.rawValue)-\(kind.rawValue)-\(teamID ?? "all")"
    }

    /// The sport and situation a `ruleID` stands for, if it's a situation rule's.
    static func parse(_ ruleID: String) -> (sport: SportType, kind: ClutchMoment.Kind)? {
        let parts = ruleID.split(separator: "-", maxSplits: 3).map(String.init)
        guard parts.count == 4, parts[0] == prefix,
              let sport = SportType(rawValue: parts[1]),
              let kind = ClutchMoment.Kind(rawValue: parts[2]) else { return nil }
        return (sport, kind)
    }

    /// Favorite team IDs per sport, as the main league's games carry them (the only
    /// place the app learns which sport a followed team plays).
    static func favoriteTeamIDs(games: [Game], favorites: Set<String>) -> [SportType: [String]] {
        guard !favorites.isEmpty else { return [:] }
        var out: [SportType: Set<String>] = [:]
        for game in games {
            guard let league = game.idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:)) else { continue }
            let sport = SportType(league: league)
            guard AlertRule.mainLeague(for: sport) == league else { continue }
            for id in [game.idHomeTeam, game.idAwayTeam].compactMap({ $0 }) where favorites.contains(id) {
                out[sport, default: []].insert(id)
            }
        }
        return out.mapValues { $0.sorted() }
    }

    /// The situation rules `prefs` asks for: one per situation and favorite team, or one
    /// per situation for the whole league.
    static func rules(prefs: SituationAlertPrefs, favoriteTeamIDs: [SportType: [String]]) -> [AlertRule] {
        var out: [AlertRule] = []
        for sport in CustomAlertCatalog.situationSports {
            let teams: [String?] = prefs.coversAllGames(sport) ? [nil] : (favoriteTeamIDs[sport] ?? [])
            for kind in prefs.enabledKinds(sport: sport) {
                for team in teams {
                    let rule = AlertRule(
                        id: ruleID(sport: sport, kind: kind, teamID: team),
                        kind: .gameSituation, sport: sport, teamID: team, situation: kind
                    )
                    if rule.isValid { out.append(rule) }
                }
            }
        }
        return out
    }
}

// MARK: - Caps

enum CustomAlertPolicy {
    /// The limits the UI enforces. A local Pro entitlement wins (the server's answer
    /// may predate the purchase); otherwise the server's last word, else the free tier.
    static func limits(localIsPro: Bool, server: CustomAlertLimits?) -> CustomAlertLimits {
        localIsPro ? .pro : (server ?? .free)
    }

    /// `rules` with the athlete's rules swapped for `new`, keeping their place in the
    /// order (the server's cap keeps rules first come, first served).
    static func replacing(athleteID: String, with new: [AlertRule], in rules: [AlertRule]) -> [AlertRule] {
        guard let first = rules.firstIndex(where: { $0.athleteID == athleteID }) else { return rules + new }
        var out = rules
        out.removeAll { $0.athleteID == athleteID }
        let position = rules[..<first].filter { $0.athleteID != athleteID }.count
        out.insert(contentsOf: new, at: position)
        return out
    }

    /// Whether saving `new` for `athleteID` goes over `limits`: any of the new rules
    /// would be dropped. What's already over the cap (a lapsed subscription) doesn't
    /// block edits that stay within it.
    static func exceedsCap(new: [AlertRule], athleteID: String, playerRules: [AlertRule], limits: CustomAlertLimits) -> Bool {
        let combined = replacing(athleteID: athleteID, with: new, in: playerRules)
        let dropped = Set(limits.apply(to: combined).droppedIDs)
        return new.contains { $0.isValid && dropped.contains($0.id) }
    }

    /// The order rules go up in: player rules first, so on the free tier the one
    /// player rule isn't crowded out by situations (which free can't have anyway).
    static func registrationRules(playerRules: [AlertRule], situationRules: [AlertRule]) -> [AlertRule] {
        var seen = Set<String>()
        return (playerRules + situationRules).filter { seen.insert($0.id).inserted }
    }
}
