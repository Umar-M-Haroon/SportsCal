//
//  CustomAlertRegistrar.swift
//  SportsCal
//
//  Custom live alerts on the device: `CustomAlertStore` keeps the install's player
//  rules and Game Alerts choices plus the server's last answer (limits, Pro verdict,
//  dropped rules), and `CustomAlertRegistrar` keeps `POST /notifications/custom` in
//  step with them, the way `SoccerAlertRegistrar` does for soccer match alerts: on
//  every change, on launch and foreground (re-sent weekly even when unchanged, since
//  the server forgets after 30 days), and when the push token changes.
//
//  `CustomAlertActions` handles the notification's "Mute" and "Turn off" buttons.
//

import Foundation
import SportsCalModel
import RevenueCat
import UserNotifications

extension Notification.Name {
    /// Posted when the install's custom alert rules or Game Alerts choices change, so
    /// ContentView (which has the games and favorites) re-syncs the registration.
    static let customAlertRulesDidChange = Notification.Name("CustomAlertRulesDidChange")
}

// MARK: - Store

@Observable
final class CustomAlertStore {
    static let shared = CustomAlertStore()

    /// Player rules (plays and milestones), in the order they were made: on a tier
    /// that can't keep them all, the server keeps the earliest.
    private(set) var playerRules: [AlertRule]
    private(set) var situationPrefs: SituationAlertPrefs
    /// From the server's last answer.
    private(set) var serverLimits: CustomAlertLimits?
    private(set) var serverIsPro: Bool?
    /// Rules the server said it won't act on (over the cap, or invalid). They stay
    /// here, shown as paused, so subscribing brings them back.
    private(set) var droppedRuleIDs: Set<String>

    /// The situation rules last derived from games and favorites, for re-syncs that
    /// run without them (a notification action in the background).
    @ObservationIgnored private(set) var cachedSituationRules: [AlertRule]

    @ObservationIgnored private let defaults: UserDefaults?

    private enum Keys {
        static let playerRules = "customAlerts.playerRules"
        static let situations = "customAlerts.situations"
        static let serverLimits = "customAlerts.serverLimits"
        static let serverIsPro = "customAlerts.serverIsPro"
        static let dropped = "customAlerts.droppedRuleIDs"
        static let situationCache = "customAlerts.situationRulesCache"
    }

    init(defaults: UserDefaults? = UserDefaults(suiteName: "group.Komodo.SportsCal")) {
        self.defaults = defaults
        func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
            guard let data = defaults?.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        playerRules = decode([AlertRule].self, Keys.playerRules) ?? []
        situationPrefs = decode(SituationAlertPrefs.self, Keys.situations) ?? SituationAlertPrefs()
        serverLimits = decode(CustomAlertLimits.self, Keys.serverLimits)
        serverIsPro = defaults?.object(forKey: Keys.serverIsPro) as? Bool
        droppedRuleIDs = Set(defaults?.stringArray(forKey: Keys.dropped) ?? [])
        cachedSituationRules = decode([AlertRule].self, Keys.situationCache) ?? []
    }

    private func write<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults?.set(data, forKey: key) }
    }

    private func changed() {
        NotificationCenter.default.post(name: .customAlertRulesDidChange, object: nil)
    }

    // MARK: Limits

    var limits: CustomAlertLimits {
        CustomAlertPolicy.limits(localIsPro: SubscriptionManager.shared.isPro, server: serverLimits)
    }

    func isPaused(_ rule: AlertRule) -> Bool { droppedRuleIDs.contains(rule.id) }

    // MARK: Player rules

    func rules(forAthlete athleteID: String) -> [AlertRule] {
        playerRules.filter { $0.athleteID == athleteID }
    }

    /// Replaces the athlete's rules. Callers check `CustomAlertPolicy.exceedsCap` first.
    func setRules(_ rules: [AlertRule], forAthlete athleteID: String) {
        let updated = CustomAlertPolicy.replacing(athleteID: athleteID, with: rules, in: playerRules)
        guard updated != playerRules else { return }
        playerRules = updated
        write(playerRules, Keys.playerRules)
        changed()
    }

    func removeRules(forAthlete athleteID: String) {
        setRules([], forAthlete: athleteID)
    }

    /// "Turn off this alert": a player rule goes; a situation rule turns that situation
    /// off for its sport. Returns whether anything changed.
    @discardableResult
    func turnOff(ruleID: String) -> Bool {
        if playerRules.contains(where: { $0.id == ruleID }) {
            playerRules.removeAll { $0.id == ruleID }
            write(playerRules, Keys.playerRules)
            changed()
            return true
        }
        if let situation = SituationAlertRules.parse(ruleID), situationPrefs.isOn(situation.kind, sport: situation.sport) {
            setSituation(situation.kind, sport: situation.sport, on: false)
            return true
        }
        return false
    }

    // MARK: Situations

    func setSituation(_ kind: ClutchMoment.Kind, sport: SportType, on: Bool) {
        var prefs = situationPrefs
        prefs.set(kind, sport: sport, on: on)
        updateSituations(prefs)
    }

    func setCoversAllGames(_ sport: SportType, _ allGames: Bool) {
        var prefs = situationPrefs
        prefs.setCoversAllGames(sport, allGames)
        updateSituations(prefs)
    }

    private func updateSituations(_ prefs: SituationAlertPrefs) {
        guard prefs != situationPrefs else { return }
        situationPrefs = prefs
        write(prefs, Keys.situations)
        // Keep the background re-sync's copy in step with what was just turned off.
        cachedSituationRules = cachedSituationRules.filter { rule in
            guard let situation = SituationAlertRules.parse(rule.id) else { return false }
            return prefs.isOn(situation.kind, sport: situation.sport)
                && prefs.coversAllGames(situation.sport) == (rule.teamID == nil)
        }
        write(cachedSituationRules, Keys.situationCache)
        changed()
    }

    func cacheSituationRules(_ rules: [AlertRule]) {
        guard rules != cachedSituationRules else { return }
        cachedSituationRules = rules
        write(rules, Keys.situationCache)
    }

    // MARK: Server answer

    func apply(_ response: CustomAlertRegistrationResponse) {
        serverLimits = response.limits
        serverIsPro = response.isPro
        droppedRuleIDs = Set(response.droppedRuleIDs)
        write(response.limits, Keys.serverLimits)
        defaults?.set(response.isPro, forKey: Keys.serverIsPro)
        defaults?.set(response.droppedRuleIDs, forKey: Keys.dropped)
    }

    func clearDropped() {
        guard !droppedRuleIDs.isEmpty else { return }
        droppedRuleIDs = []
        defaults?.removeObject(forKey: Keys.dropped)
    }
}

// MARK: - Registrar

enum CustomAlertRegistrar {
    private static let suiteName = "group.Komodo.SportsCal"
    private static let tokenKey = "apnsDeviceToken"
    private static let lastSentKey = "customAlertLastRegistration"
    private static let lastSentDateKey = "customAlertLastRegistrationDate"
    private static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60

    static var pushToken: String? {
        guard let token = UserDefaults(suiteName: suiteName)?.string(forKey: tokenKey), !token.isEmpty else { return nil }
        return token
    }

    private static var revenueCatAppUserID: String? {
        Purchases.isConfigured ? Purchases.shared.appUserID : nil
    }

    /// Sends the registration if it differs from the last one this server accepted.
    ///
    /// - Parameters:
    ///   - games: The schedule, to find which sport each favorite team plays. Nil (a
    ///     background notification action) reuses the situation rules last derived.
    ///   - favoriteTeamIDs: `Favorites.teamIDs`.
    static func sync(
        games: [Game]?,
        favoriteTeamIDs: Set<String>,
        store: CustomAlertStore = .shared,
        isPro: Bool = SubscriptionManager.shared.isPro
    ) async {
        guard let defaults = UserDefaults(suiteName: suiteName), let token = pushToken else { return }

        let situationRules: [AlertRule]
        if let games, !games.isEmpty {
            let teams = SituationAlertRules.favoriteTeamIDs(games: games, favorites: favoriteTeamIDs)
            situationRules = SituationAlertRules.rules(prefs: store.situationPrefs, favoriteTeamIDs: teams)
            store.cacheSituationRules(situationRules)
        } else {
            situationRules = store.cachedSituationRules
        }
        let rules = CustomAlertPolicy.registrationRules(playerRules: store.playerRules, situationRules: situationRules)

        let registration = CustomAlertRegistration(
            token: token,
            revenueCatAppUserID: revenueCatAppUserID,
            sandbox: NetworkHandler.isSandboxAPNS,
            rules: rules
        )
        // Keyed by server, and by the local Pro state: subscribing re-sends unchanged
        // rules so the server re-checks the entitlement and lifts the cap.
        let encoded = String(decoding: (try? JSONEncoder().encode(registration)) ?? Data(), as: UTF8.self)
        let fingerprint = NetworkHandler.baseURL() + "|pro=\(isPro)|" + encoded
        let lastSentAt = defaults.object(forKey: lastSentDateKey) as? Date ?? .distantPast
        let isFresh = Date().timeIntervalSince(lastSentAt) < refreshInterval
        guard defaults.string(forKey: lastSentKey) != fingerprint || !isFresh else { return }

        if rules.isEmpty {
            // Nothing to unregister if this server never had a registration.
            guard defaults.string(forKey: lastSentKey) != nil else { return }
            do {
                try await NetworkHandler.unregisterCustomAlerts(token: token)
                defaults.set(fingerprint, forKey: lastSentKey)
                defaults.set(Date(), forKey: lastSentDateKey)
                store.clearDropped()
                AppLogger.notifications.info("Custom alerts unregistered")
            } catch {
                AppLogger.notifications.error("Custom alert unregistration failed: \(error.localizedDescription)")
            }
            return
        }

        do {
            let response = try await NetworkHandler.registerCustomAlerts(registration)
            store.apply(response)
            defaults.set(fingerprint, forKey: lastSentKey)
            defaults.set(Date(), forKey: lastSentDateKey)
            AppLogger.notifications.info("Custom alerts registered: \(response.rules.count) kept, \(response.droppedRuleIDs.count) dropped, pro=\(response.isPro)")
        } catch {
            AppLogger.notifications.error("Custom alert registration failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Notification actions

enum CustomAlertActions {
    /// Situation alerts have no player to mute; a category with only "Turn off" for
    /// them, used if the server sends situation alerts under it.
    static let situationCategory = "CUSTOM_ALERT_SITUATION"

    /// The custom alert categories, for `UNUserNotificationCenter.setNotificationCategories`.
    static var categories: Set<UNNotificationCategory> {
        let mute = UNNotificationAction(
            identifier: CustomAlertNotification.muteActionID,
            title: "Mute for This Game",
            options: []
        )
        let turnOff = UNNotificationAction(
            identifier: CustomAlertNotification.turnOffActionID,
            title: "Turn Off This Alert",
            options: [.destructive]
        )
        return [
            UNNotificationCategory(identifier: CustomAlertNotification.category,
                                   actions: [mute, turnOff], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: situationCategory,
                                   actions: [turnOff], intentIdentifiers: [], options: []),
        ]
    }

    /// Adds the custom alert categories to whatever is registered already.
    static func registerCategories() {
        let ours = categories
        let ids = Set(ours.map(\.identifier))
        Task {
            let center = UNUserNotificationCenter.current()
            let existing = await center.notificationCategories()
            center.setNotificationCategories(existing.filter { !ids.contains($0.identifier) }.union(ours))
        }
    }

    /// Whether `actionIdentifier` is one of ours (so the tap shouldn't open the game).
    static func handles(_ actionIdentifier: String) -> Bool {
        actionIdentifier == CustomAlertNotification.muteActionID
            || actionIdentifier == CustomAlertNotification.turnOffActionID
    }

    /// Runs a "Mute" or "Turn off" tap.
    static func perform(actionIdentifier: String, userInfo: [AnyHashable: Any]) async {
        let eventID = userInfo[CustomAlertNotification.eventIDKey] as? String
        let ruleID = userInfo[CustomAlertNotification.ruleIDKey] as? String
        let athleteID = userInfo[CustomAlertNotification.athleteIDKey] as? String
        switch actionIdentifier {
        case CustomAlertNotification.muteActionID:
            guard let token = CustomAlertRegistrar.pushToken, let eventID else { return }
            // A player alert mutes every rule about the player for the game; a
            // situation alert (no athlete) mutes just its rule.
            let request = CustomAlertMuteRequest(
                token: token, eventID: eventID,
                ruleID: athleteID == nil ? ruleID : nil,
                athleteID: athleteID,
                sandbox: NetworkHandler.isSandboxAPNS
            )
            do {
                try await NetworkHandler.muteCustomAlert(request)
                MonetizationTelemetry.customAlertAction("mute")
            } catch {
                AppLogger.notifications.error("Custom alert mute failed: \(error.localizedDescription)")
            }
        case CustomAlertNotification.turnOffActionID:
            guard let ruleID else { return }
            // The store posts `.customAlertRulesDidChange`, which ContentView syncs on
            // when it's around; sync here too for a background launch without it.
            if CustomAlertStore.shared.turnOff(ruleID: ruleID) {
                MonetizationTelemetry.customAlertAction("turn_off")
                await CustomAlertRegistrar.sync(games: nil, favoriteTeamIDs: [])
            }
        default:
            break
        }
    }
}
