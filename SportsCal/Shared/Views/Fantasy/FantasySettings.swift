//
//  FantasySettings.swift
//  SportsCal
//
//  The user's fantasy setup: which scoring each sport uses (a preset, their custom
//  copy, or an imported league's), the custom scorings, and imported leagues with
//  the team that's theirs. Everything but ESPN cookies lives in standard defaults and
//  syncs through `CloudSyncManager` (the "fantasy.*" keys); ESPN's `espn_s2` / `SWID`
//  stay in this device's Keychain and are never synced or sent to our server.
//
//  Custom scoring and league import are Pro (`ProFeature.fantasyLeagues`). Like
//  themes, the choice survives a lapse; what the screens use is the *effective*
//  scoring, which falls back to the sport's default preset while not entitled.
//

import Foundation
import Security
import SportsCalModel

@Observable
final class FantasySettings {
    static let shared = FantasySettings()

    /// Which scoring a sport uses.
    enum Selection: Codable, Hashable, Sendable {
        case preset(String)
        case custom
        case league(String)
    }

    enum Keys {
        static let selections = "fantasy.selections"
        static let custom = "fantasy.customScoring"
        static let leagues = "fantasy.leagues"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var remoteObserver: NSObjectProtocol?

    /// Sport raw value → selection.
    private(set) var selections: [String: Selection]
    /// Sport raw value → the user's edited scoring.
    private(set) var customScorings: [String: FantasyScoring]
    private(set) var leagues: [FantasyLeague]

    init(defaults: UserDefaults = .standard, observesCloud: Bool = true) {
        self.defaults = defaults
        selections = Self.decode([String: Selection].self, defaults.data(forKey: Keys.selections)) ?? [:]
        customScorings = Self.decode([String: FantasyScoring].self, defaults.data(forKey: Keys.custom)) ?? [:]
        leagues = Self.decode([FantasyLeague].self, defaults.data(forKey: Keys.leagues)) ?? []
        if observesCloud {
            remoteObserver = NotificationCenter.default.addObserver(
                forName: CloudSyncManager.didApplyRemoteUpdateNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.reloadFromDefaults() }
        }
    }

    /// Picks up values another device wrote (via iCloud KVS → defaults).
    func reloadFromDefaults() {
        let s = Self.decode([String: Selection].self, defaults.data(forKey: Keys.selections)) ?? [:]
        let c = Self.decode([String: FantasyScoring].self, defaults.data(forKey: Keys.custom)) ?? [:]
        let l = Self.decode([FantasyLeague].self, defaults.data(forKey: Keys.leagues)) ?? []
        if s != selections { selections = s }
        if c != customScorings { customScorings = c }
        if l != leagues { leagues = l }
    }

    // MARK: Entitlement

    /// Whether custom scoring and imported leagues are usable (Pro).
    var isEntitled: Bool { SubscriptionManager.shared.canUse(.fantasyLeagues) }

    // MARK: Scoring

    func selection(for sport: SportType) -> Selection {
        selections[sport.rawValue] ?? .preset(FantasyScoring.defaultScoring(for: sport)?.id ?? "")
    }

    /// The scoring screens use: the selection while it's usable, else the default preset.
    func scoring(for sport: SportType) -> FantasyScoring? {
        resolve(selection(for: sport), sport: sport, entitled: isEntitled)
            ?? FantasyScoring.defaultScoring(for: sport)
    }

    /// Whether the selection is in effect, or is being held back (lapsed Pro, deleted league).
    func isSelectionInEffect(for sport: SportType) -> Bool {
        resolve(selection(for: sport), sport: sport, entitled: isEntitled) != nil
    }

    private func resolve(_ selection: Selection, sport: SportType, entitled: Bool) -> FantasyScoring? {
        switch selection {
        case .preset(let id):
            return FantasyScoring.presets(for: sport).first { $0.id == id }
        case .custom:
            return entitled ? customScoring(for: sport) : nil
        case .league(let id):
            guard entitled, let league = leagues.first(where: { $0.id == id && $0.sport == sport }) else { return nil }
            return league.scoring
        }
    }

    func select(_ selection: Selection, for sport: SportType) {
        selections[sport.rawValue] = selection
        persist(selections, Keys.selections)
    }

    /// The user's custom scoring, or a copy of the default preset to start editing from.
    func customScoring(for sport: SportType) -> FantasyScoring? {
        if let custom = customScorings[sport.rawValue] { return custom }
        guard var base = FantasyScoring.defaultScoring(for: sport) else { return nil }
        base.id = Self.customID(for: sport)
        base.name = "My scoring"
        return base
    }

    var hasCustomScoring: Bool { !customScorings.isEmpty }

    func hasCustomScoring(for sport: SportType) -> Bool { customScorings[sport.rawValue] != nil }

    func setCustomScoring(_ scoring: FantasyScoring) {
        var scoring = scoring
        scoring.id = Self.customID(for: scoring.sport)
        customScorings[scoring.sport.rawValue] = scoring
        persist(customScorings, Keys.custom)
    }

    static func customID(for sport: SportType) -> String { "custom.\(sport.rawValue)" }

    // MARK: Leagues

    func leagues(for sport: SportType) -> [FantasyLeague] { leagues.filter { $0.sport == sport } }

    func league(id: String) -> FantasyLeague? { leagues.first { $0.id == id } }

    /// Adds or replaces a league. A re-sync keeps the team the user picked when the
    /// import itself didn't know who they are.
    func upsert(_ league: FantasyLeague) {
        var league = league
        if let index = leagues.firstIndex(where: { $0.id == league.id }) {
            if league.myTeamID == nil || !league.teams.contains(where: { $0.id == league.myTeamID }) {
                let kept = leagues[index].myTeamID
                league.myTeamID = league.teams.contains { $0.id == kept } ? kept : league.myTeamID
            }
            leagues[index] = league
        } else {
            leagues.append(league)
        }
        persist(leagues, Keys.leagues)
    }

    func setMyTeam(_ teamID: String?, leagueID: String) {
        guard let index = leagues.firstIndex(where: { $0.id == leagueID }) else { return }
        leagues[index].myTeamID = teamID
        persist(leagues, Keys.leagues)
    }

    func removeLeague(id: String) {
        guard let league = league(id: id) else { return }
        leagues.removeAll { $0.id == id }
        persist(leagues, Keys.leagues)
        if selection(for: league.sport) == .league(id) {
            select(.preset(FantasyScoring.defaultScoring(for: league.sport)?.id ?? ""), for: league.sport)
        }
        if league.provider == .espn { ESPNFantasyCredentials.delete(leagueID: league.providerLeagueID) }
    }

    /// Athlete IDs on the user's own teams in usable leagues: the active league's team
    /// when one is selected, every league's otherwise.
    func myRosterIDs(for sport: SportType) -> Set<String> {
        guard isEntitled else { return [] }
        let pool: [FantasyLeague]
        if case .league(let id) = selection(for: sport), let active = league(id: id) {
            pool = [active]
        } else {
            pool = leagues(for: sport)
        }
        return Set(pool.compactMap(\.myTeam).flatMap(\.athleteIDs))
    }

    /// Starters on the user's teams (same pool as `myRosterIDs`).
    func myStarterIDs(for sport: SportType) -> Set<String> {
        guard isEntitled else { return [] }
        let pool: [FantasyLeague]
        if case .league(let id) = selection(for: sport), let active = league(id: id) {
            pool = [active]
        } else {
            pool = leagues(for: sport)
        }
        return Set(pool.compactMap(\.myTeam).flatMap { $0.starterIDs ?? [] })
    }

    // MARK: Persistence

    private func persist<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}

extension FantasySettings.Selection {
    /// The display name of what's selected, given the settings that resolve it.
    func name(in settings: FantasySettings, sport: SportType) -> String {
        switch self {
        case .preset(let id): return FantasyScoring.preset(id: id)?.name ?? "Default"
        case .custom: return settings.customScoring(for: sport)?.name ?? "My scoring"
        case .league(let id): return settings.league(id: id)?.name ?? "League"
        }
    }
}

// MARK: - ESPN cookies (Keychain, this device only)

/// A private ESPN league's `espn_s2` / `SWID` cookies, kept in the Keychain per league
/// so a re-sync can reuse them. Never synced (ThisDeviceOnly) and never sent anywhere
/// but ESPN.
struct ESPNFantasyCredentials: Codable, Equatable {
    var espnS2: String
    var swid: String

    private static let service = "com.KomodoLLC.SportsCal.espnFantasy"

    static func load(leagueID: String) -> ESPNFantasyCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: leagueID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(ESPNFantasyCredentials.self, from: data)
    }

    static func save(_ credentials: ESPNFantasyCredentials, leagueID: String) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        delete(leagueID: leagueID)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: leagueID,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete(leagueID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: leagueID,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Seasons

enum FantasySeason {
    /// The NFL fantasy season a date falls in: the year it kicked off (Jan/Feb
    /// playoffs belong to the previous year's season).
    static func current(_ date: Date = Date(), calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: date)
        return calendar.component(.month, from: date) < 3 ? year - 1 : year
    }
}
