//
//  GolfAlertRegistrar.swift
//  SportsCal
//
//  Keeps the server's golf alert registration for this install in step with the app:
//  the push token, the followed players, and the alert kinds chosen in Settings. The
//  server's GolfAlertJob does the rest, the way SoccerAlertRegistrar works for teams.
//
//  Following a player is the opt-in: favourites are stored by the name the leaderboard
//  shows, which is what the server matches on, so they go up as they are.
//

import Foundation
import SportsCalModel

enum GolfAlertRegistrar {
    private static let suiteName = "group.Komodo.SportsCal"
    private static let tokenKey = "apnsDeviceToken"
    private static let lastSentKey = "golfAlertLastRegistration"
    private static let lastSentDateKey = "golfAlertLastRegistrationDate"
    private static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
    /// The server takes at most this many.
    static let playerLimit = 100

    /// Sends the registration if it differs from the last one this server accepted.
    static func sync(players: Set<String>, storage: UserDefaultStorage) async {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let token = defaults.string(forKey: tokenKey), !token.isEmpty else { return }
        let registration = GolfAlertRegistration(
            token: token,
            players: Array(players.sorted().prefix(playerLimit)),
            kinds: GolfAlertKind.allCases.filter(storage.golfAlertKinds.contains)
        )
        // Keyed by server, so switching environments registers with the new one.
        let fingerprint = NetworkHandler.baseURL() + "|" + String(decoding: (try? JSONEncoder().encode(registration)) ?? Data(), as: UTF8.self)
        // The server forgets a registration after 30 days, so an unchanged one is
        // still re-sent once it's a week old.
        let lastSentAt = defaults.object(forKey: lastSentDateKey) as? Date ?? .distantPast
        let isFresh = Date().timeIntervalSince(lastSentAt) < refreshInterval
        guard defaults.string(forKey: lastSentKey) != fingerprint || !isFresh else { return }
        // Nothing to unregister if this server never had a registration.
        if registration.players.isEmpty, defaults.string(forKey: lastSentKey) == nil { return }
        do {
            try await NetworkHandler.registerGolfAlerts(registration)
            defaults.set(fingerprint, forKey: lastSentKey)
            defaults.set(Date(), forKey: lastSentDateKey)
            AppLogger.notifications.info("Golf alerts registered: \(registration.players.count) players, \(registration.kinds.count) kinds")
        } catch {
            AppLogger.notifications.error("Golf alert registration failed: \(error.localizedDescription)")
        }
    }
}
