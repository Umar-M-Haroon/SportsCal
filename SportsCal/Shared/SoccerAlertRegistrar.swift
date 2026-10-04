//
//  SoccerAlertRegistrar.swift
//  SportsCal
//
//  Keeps the server's soccer alert registration for this install in step with the
//  app: the push token, the soccer teams with alerts on (within the free
//  allowance, like `TeamAlertScheduler`), and the alert kinds chosen in Settings.
//  The server's SoccerAlertJob does the rest.
//
//  Teams go up by the names this install's games carry, since that's what the
//  server matches live games on. A team with no soccer game in the feed yet is
//  picked up on a later sync.
//

import Foundation
import SportsCalModel

extension Notification.Name {
    /// Posted when APNS hands the app a (possibly new) device token.
    static let apnsDeviceTokenDidUpdate = Notification.Name("APNSDeviceTokenDidUpdate")
}

enum SoccerAlertRegistrar {
    private static let suiteName = "group.Komodo.SportsCal"
    private static let tokenKey = "apnsDeviceToken"
    private static let lastSentKey = "soccerAlertLastRegistration"

    /// Soccer team names, as `games` carry them, for the teams with alerts on.
    static func teamNames(games: [Game], teamIDs: Set<String>, isPro: Bool) -> [String] {
        let allowed = isPro ? teamIDs : Set(teamIDs.sorted().prefix(NotificationGate.freeTeamAlertLimit))
        guard !allowed.isEmpty else { return [] }
        func isAllowed(id: String?, name: String) -> Bool {
            if let id, allowed.contains(id) { return true }
            if let id = TeamsManager.shared.teamID(forName: name), allowed.contains(id) { return true }
            return false
        }
        var names = Set<String>()
        for game in games {
            guard let league = game.idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:)),
                  SportType(league: league) == .soccer else { continue }
            if isAllowed(id: game.idHomeTeam, name: game.strHomeTeam) { names.insert(game.strHomeTeam) }
            if isAllowed(id: game.idAwayTeam, name: game.strAwayTeam) { names.insert(game.strAwayTeam) }
        }
        return names.sorted()
    }

    /// Sends the registration if it differs from the last one this server accepted.
    static func sync(games: [Game], storage: UserDefaultStorage, isPro: Bool) async {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let token = defaults.string(forKey: tokenKey), !token.isEmpty else { return }
        let registration = SoccerAlertRegistration(
            token: token,
            teams: teamNames(games: games, teamIDs: storage.teamAlertTeamIDs, isPro: isPro),
            kinds: SoccerAlertKind.allCases.filter(storage.soccerAlertKinds.contains)
        )
        // Keyed by server, so switching environments registers with the new one.
        let fingerprint = NetworkHandler.baseURL() + "|" + String(decoding: (try? JSONEncoder().encode(registration)) ?? Data(), as: UTF8.self)
        guard defaults.string(forKey: lastSentKey) != fingerprint else { return }
        // Nothing to unregister if this server never had a registration.
        if registration.teams.isEmpty, defaults.string(forKey: lastSentKey) == nil { return }
        do {
            try await NetworkHandler.registerSoccerAlerts(registration)
            defaults.set(fingerprint, forKey: lastSentKey)
            AppLogger.notifications.info("Soccer alerts registered: \(registration.teams.count) teams, \(registration.kinds.count) kinds")
        } catch {
            AppLogger.notifications.error("Soccer alert registration failed: \(error.localizedDescription)")
        }
    }
}
