//
//  WatchSyncService.swift
//  SportsCalWatch
//
//  Watch-side WatchConnectivity handler.
//  Receives sport prefs, favorites, and hidden competitions from iPhone.
//  Sends favorites changes back to iPhone.
//

import Foundation
import Observation
import WatchConnectivity

@Observable
final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    /// Called when preferences are updated from iPhone
    var onPreferencesUpdated: (() -> Void)?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Sending to iPhone

    func sendFavoritesUpdate(_ favorites: [String]) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["action": "updateFavorites", "favorites": favorites],
            replyHandler: nil
        )
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            // Read any queued application context
            applyContext(session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyContext(applicationContext)
    }

    // MARK: - Apply Context

    private func applyContext(_ context: [String: Any]) {
        let defaults = UserDefaults.standard

        // Sport preferences
        if let nba = context["shouldShowNBA"] as? Bool { defaults.set(nba, forKey: "shouldShowNBA") }
        if let soccer = context["shouldShowSoccer"] as? Bool { defaults.set(soccer, forKey: "shouldShowSoccer") }
        if let nhl = context["shouldShowNHL"] as? Bool { defaults.set(nhl, forKey: "shouldShowNHL") }
        if let mlb = context["shouldShowMLB"] as? Bool { defaults.set(mlb, forKey: "shouldShowMLB") }
        if let nfl = context["shouldShowNFL"] as? Bool { defaults.set(nfl, forKey: "shouldShowNFL") }
        if let golf = context["shouldShowGolf"] as? Bool { defaults.set(golf, forKey: "shouldShowGolf") }
        if let tennis = context["shouldShowTennis"] as? Bool { defaults.set(tennis, forKey: "shouldShowTennis") }
        if let racing = context["shouldShowRacing"] as? Bool { defaults.set(racing, forKey: "shouldShowRacing") }

        // Favorites-only per-sport
        if let v = context["favoritesOnlyNBA"] as? Bool { defaults.set(v, forKey: "favoritesOnlyNBA") }
        if let v = context["favoritesOnlySoccer"] as? Bool { defaults.set(v, forKey: "favoritesOnlySoccer") }
        if let v = context["favoritesOnlyNHL"] as? Bool { defaults.set(v, forKey: "favoritesOnlyNHL") }
        if let v = context["favoritesOnlyMLB"] as? Bool { defaults.set(v, forKey: "favoritesOnlyMLB") }
        if let v = context["favoritesOnlyNFL"] as? Bool { defaults.set(v, forKey: "favoritesOnlyNFL") }
        if let v = context["favoritesOnlyGolf"] as? Bool { defaults.set(v, forKey: "favoritesOnlyGolf") }
        if let v = context["favoritesOnlyTennis"] as? Bool { defaults.set(v, forKey: "favoritesOnlyTennis") }
        if let v = context["favoritesOnlyRacing"] as? Bool { defaults.set(v, forKey: "favoritesOnlyRacing") }

        // Favorites
        if let favorites = context["favorites"] as? [String] {
            defaults.set(favorites, forKey: "Favorites")
        }

        // Hidden competitions
        if let hidden = context["hiddenCompetitions"] as? [String] {
            defaults.set(hidden, forKey: "hiddenCompetitions")
        }

        DispatchQueue.main.async { [weak self] in
            self?.onPreferencesUpdated?()
        }
    }
}
