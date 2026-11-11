//
//  Favorites.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/13/21.
//

import Foundation
import SwiftUI
import SportsCalModel

@Observable
class Favorites: Equatable {
    /// Resolved TheSportsDB team IDs. Source of truth post-migration.
    private(set) var teamIDs: Set<String>
    /// Names from the pre-v2 store that didn't resolve to an ID via TeamsManager.
    /// Kept so users don't lose intent if the teams cache wasn't populated yet at
    /// migration time; retried whenever TeamsManager refreshes.
    private(set) var legacyTeamNames: Set<String>
    private(set) var players: Set<String>
    /// Names of followed teams the directory doesn't carry, by ID: college football
    /// teams (`ncaaf-…`) and college basketball teams outside it. Lets `teams` list them.
    private(set) var collegeNames: [String: String]

    private let saveKey = "Favorites"
    private let playerSaveKey = "FavoritePlayers"
    private static let currentSchemaVersion = 2
    /// Set once `scopeCollegeFollows` has run on this device.
    private static let collegeScopedKey = "Favorites.collegeFollowsScoped"

    private var defaults: UserDefaults? {
        #if os(watchOS)
        return UserDefaults.standard
        #else
        return UserDefaults(suiteName: "group.Komodo.SportsCal")
        #endif
    }

    init() {
        let store: UserDefaults? = {
            #if os(watchOS)
            return UserDefaults.standard
            #else
            return UserDefaults(suiteName: "group.Komodo.SportsCal")
            #endif
        }()
        let raw = store?.object(forKey: "Favorites")
        let (ids, legacy, names) = Favorites.decodePayload(raw)
        teamIDs = ids
        legacyTeamNames = legacy
        collegeNames = names
        players = Set(store?.stringArray(forKey: "FavoritePlayers") ?? [])

        // First-launch migration: when raw was the legacy [String] shape,
        // attempt to resolve names → IDs via TeamsManager and persist the new
        // dict shape. Anything still unresolved stays in legacyTeamNames and
        // gets retried on each TeamsManager refresh.
        if Favorites.isLegacyShape(raw) {
            attemptResolveLegacy()
            save()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTeamsManagerUpdate),
            name: .teamsManagerDidUpdate,
            object: nil
        )
    }

    /// Public name-set view for callers that still operate on canonical names
    /// (Spotlight indexing, EngagementTracker exclusions). Combines resolved
    /// canonical names with any unresolved legacy entries.
    var teams: Set<String> {
        var result = legacyTeamNames
        for id in teamIDs {
            if let name = TeamsManager.shared.team(byID: id)?.strTeam ?? collegeNames[id] {
                result.insert(name)
            }
        }
        return result
    }

    /// What push-to-start registers: team names, except that a college football team goes
    /// by its ID. The school's name is its basketball team's too, and the server matches a
    /// college football game by ID alone for builds that send them this way.
    var pushToStartKeys: Set<String> {
        var result = legacyTeamNames
        for id in teamIDs {
            if id.hasPrefix(Leagues.collegeTeamIDPrefix) {
                result.insert(id)
            } else if let name = TeamsManager.shared.team(byID: id)?.strTeam ?? collegeNames[id] {
                result.insert(name)
            }
        }
        return result
    }

    func contains(_ team: Game) -> Bool {
        if let homeID = team.idHomeTeam, !homeID.isEmpty, teamIDs.contains(homeID) { return true }
        if let awayID = team.idAwayTeam, !awayID.isEmpty, teamIDs.contains(awayID) { return true }
        if !legacyTeamNames.isEmpty {
            if legacyTeamNames.contains(team.strHomeTeam) { return true }
            if legacyTeamNames.contains(team.strAwayTeam) { return true }
        }
        // College football games always carry their own IDs, and their names resolve to
        // the school's *basketball* team in the directory.
        if team.isCollegeFootball { return false }
        // Resolve game team-name to ID via TeamsManager — handles the case
        // where the game record's idHomeTeam/idAwayTeam are nil but the name
        // resolves to a favorited team.
        if let id = TeamsManager.shared.teamID(forName: team.strHomeTeam), teamIDs.contains(id) { return true }
        if let id = TeamsManager.shared.teamID(forName: team.strAwayTeam), teamIDs.contains(id) { return true }
        return false
    }

    func matches(_ game: Game) -> Bool {
        if contains(game) { return true }
        if game.isIndividualSport {
            return game.resolvedLeaderboard.contains { containsPlayer($0.name) }
        }
        return false
    }

    func contains(_ name: String) -> Bool {
        if let id = TeamsManager.shared.teamID(forName: name), teamIDs.contains(id) { return true }
        return legacyTeamNames.contains(name) || collegeNames.values.contains(name)
    }

    // MARK: Game sides
    //
    // For a game row's follow menu. A college team goes by the ID its games carry, so a
    // football follow never follows the school's basketball team, which has its name.

    /// The ID to follow one side of `game` by, for college games; nil means go by name.
    private func collegeID(_ game: Game, home: Bool) -> String? {
        guard game.isCollegeFootball || game.isCollegeBasketball,
              let id = home ? game.idHomeTeam : game.idAwayTeam, !id.isEmpty else { return nil }
        return id
    }

    func contains(_ game: Game, home: Bool) -> Bool {
        if let id = collegeID(game, home: home) { return teamIDs.contains(id) }
        return contains(home ? game.strHomeTeam : game.strAwayTeam)
    }

    func add(_ game: Game, home: Bool) {
        let name = home ? game.strHomeTeam : game.strAwayTeam
        guard let id = collegeID(game, home: home) else { return add(name) }
        addCollege(id: id, name: name)
    }

    func remove(_ game: Game, home: Bool) {
        let name = home ? game.strHomeTeam : game.strAwayTeam
        guard let id = collegeID(game, home: home) else { return remove(name) }
        removeCollege(id: id, name: name)
    }

    private func addCollege(id: String, name: String) {
        teamIDs.insert(id)
        if TeamsManager.shared.team(byID: id) == nil { collegeNames[id] = name }
        legacyTeamNames.remove(name)
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    private func removeCollege(id: String, name: String) {
        teamIDs.remove(id)
        collegeNames[id] = nil
        legacyTeamNames.remove(name)
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    func containsHome(_ home: String) -> Bool { contains(home) }
    func containsAway(_ away: String) -> Bool { contains(away) }

    func containsPlayer(_ name: String) -> Bool {
        players.contains(name)
    }

    func add(_ favorite: String) {
        if let id = TeamsManager.shared.teamID(forName: favorite) {
            teamIDs.insert(id)
            // If we'd previously stashed this name as legacy, clean it up.
            legacyTeamNames.remove(favorite)
        } else {
            legacyTeamNames.insert(favorite)
        }
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    func remove(_ favorite: String) {
        if let id = TeamsManager.shared.teamID(forName: favorite) {
            teamIDs.remove(id)
        }
        legacyTeamNames.remove(favorite)
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    // MARK: Team-based
    //
    // For callers holding a real `Team` (team page, teams list). Going by `idTeam` skips
    // the name → ID lookup, which can resolve to the wrong club when two teams share a
    // name or a team has been renamed. Only ids TeamsManager knows count: `getTeams(for:)`
    // builds stand-in teams whose `idTeam` is an event id or a name, and an unknown id
    // would also be missing from `teams` (push-to-start, Spotlight). Those go by name.

    /// The team's id when it is a real, known TheSportsDB team id, or a college team's
    /// (`league` says when a bare id is college basketball's).
    private func knownID(_ team: Team, league: Leagues? = nil) -> String? {
        guard let id = team.idTeam, !id.isEmpty else { return nil }
        if id.hasPrefix(Leagues.collegeTeamIDPrefix) || league == .ncaaMBBTournament { return id }
        return TeamsManager.shared.team(byID: id) != nil ? id : nil
    }

    func contains(team: Team, league: Leagues? = nil) -> Bool {
        if let id = knownID(team, league: league) { return teamIDs.contains(id) }
        return team.strTeam.map(contains) ?? false
    }

    func add(team: Team, league: Leagues? = nil) {
        if let id = knownID(team, league: league), id.hasPrefix(Leagues.collegeTeamIDPrefix) || league == .ncaaMBBTournament {
            return addCollege(id: id, name: team.strTeam ?? id)
        }
        guard let id = knownID(team) else {
            if let name = team.strTeam { add(name) }
            return
        }
        teamIDs.insert(id)
        if let name = team.strTeam { legacyTeamNames.remove(name) }
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    func remove(team: Team, league: Leagues? = nil) {
        if let id = knownID(team, league: league), id.hasPrefix(Leagues.collegeTeamIDPrefix) || league == .ncaaMBBTournament {
            return removeCollege(id: id, name: team.strTeam ?? id)
        }
        guard let id = knownID(team) else {
            if let name = team.strTeam { remove(name) }
            return
        }
        teamIDs.remove(id)
        if let name = team.strTeam { legacyTeamNames.remove(name) }
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    func addPlayer(_ name: String) {
        players.insert(name)
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    func removePlayer(_ name: String) {
        players.remove(name)
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    func save() {
        let payload: [String: Any] = [
            "schemaVersion": Favorites.currentSchemaVersion,
            "ids": Array(teamIDs),
            "legacy": Array(legacyTeamNames),
            "collegeNames": collegeNames
        ]
        defaults?.set(payload, forKey: saveKey)
        defaults?.set(Array(players), forKey: playerSaveKey)
    }

    /// Re-reads favorites from the appropriate UserDefaults store.
    /// Called by CloudSyncManager when remote favorites arrive via iCloud KVS.
    func reloadFromDefaults() {
        let raw = defaults?.object(forKey: saveKey)
        let (ids, legacy, names) = Favorites.decodePayload(raw)
        teamIDs = ids
        legacyTeamNames = legacy
        collegeNames = names
        players = Set(defaults?.stringArray(forKey: playerSaveKey) ?? [])
        if Favorites.isLegacyShape(raw) {
            attemptResolveLegacy()
            save()
        }
    }

    static func == (lhs: Favorites, rhs: Favorites) -> Bool {
        return lhs.teamIDs == rhs.teamIDs
            && lhs.legacyTeamNames == rhs.legacyTeamNames
            && lhs.collegeNames == rhs.collegeNames
            && lhs.players == rhs.players
    }

    // MARK: - Private

    @objc private func handleTeamsManagerUpdate() {
        // Before resolving, which would give a college name its basketball team's ID.
        let scoped = scopeCollegeFollows()
        guard scoped || !legacyTeamNames.isEmpty else { return }
        attemptResolveLegacy()
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    /// Once per device, when the college football teams are known. Follows from before
    /// college follows went by ID named the school, or carried its basketball team's
    /// directory ID, and so followed both sports. Any that names a college football team
    /// becomes a football follow. Returns whether anything changed.
    @discardableResult
    private func scopeCollegeFollows() -> Bool {
        guard defaults?.bool(forKey: Self.collegeScopedKey) != true else { return false }
        let collegeTeams = TeamsManager.shared.collegeTeams
        guard !collegeTeams.isEmpty else { return false }
        var footballIDByName: [String: String] = [:]
        for team in collegeTeams {
            if let name = team.strTeam, let id = team.idTeam { footballIDByName[name] = id }
        }
        var changed = false
        for name in Array(legacyTeamNames) {
            guard let id = footballIDByName[name] else { continue }
            legacyTeamNames.remove(name)
            teamIDs.insert(id)
            collegeNames[id] = name
            changed = true
        }
        // A follow with a stored name was made by ID already (a basketball team page or row).
        for id in Array(teamIDs) where !id.hasPrefix(Leagues.collegeTeamIDPrefix) && collegeNames[id] == nil {
            guard let name = TeamsManager.shared.team(byID: id)?.strTeam,
                  let footballID = footballIDByName[name] else { continue }
            teamIDs.remove(id)
            teamIDs.insert(footballID)
            collegeNames[footballID] = name
            changed = true
        }
        defaults?.set(true, forKey: Self.collegeScopedKey)
        if changed { save() }
        return changed
    }

    private func attemptResolveLegacy() {
        guard !legacyTeamNames.isEmpty else { return }
        var resolved: [String] = []
        for name in legacyTeamNames {
            if let id = TeamsManager.shared.teamID(forName: name) {
                teamIDs.insert(id)
                resolved.append(name)
            }
        }
        for name in resolved { legacyTeamNames.remove(name) }
    }

    /// Decodes the persisted favorites payload, tolerating both v1 (`[String]`
    /// of team names) and v2 (`{ schemaVersion, ids, legacy, collegeNames? }`) shapes.
    private static func decodePayload(_ raw: Any?) -> (ids: Set<String>, legacy: Set<String>, collegeNames: [String: String]) {
        if let dict = raw as? [String: Any] {
            let ids = (dict["ids"] as? [String]).map(Set.init) ?? []
            let legacy = (dict["legacy"] as? [String]).map(Set.init) ?? []
            let names = dict["collegeNames"] as? [String: String] ?? [:]
            return (ids, legacy, names)
        }
        if let array = raw as? [String] {
            return ([], Set(array), [:])
        }
        return ([], [], [:])
    }

    private static func isLegacyShape(_ raw: Any?) -> Bool {
        raw is [String]
    }
}

extension Notification.Name {
    static let favoritesDidChange = Notification.Name("favoritesDidChange")
}
