//
//  WatchSyncService.swift
//  SportsCal (iOS)
//
//  iPhone-side WatchConnectivity handler.
//  Sends sport prefs, favorites, and hidden competitions to Watch.
//  Receives favorites changes from Watch.
//

#if os(iOS)
import Foundation
import WatchConnectivity

final class PhoneWatchSyncService: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchSyncService()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Send Preferences to Watch

    /// Call this when sport prefs, favorites, or hidden competitions change.
    func syncAllPreferences() {
        guard WCSession.default.activationState == .activated else { return }

        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        let favorites = defaults?.stringArray(forKey: "Favorites") ?? []
        let hidden = defaults?.stringArray(forKey: "hiddenCompetitions") ?? []

        let context: [String: Any] = [
            "shouldShowNBA": defaults?.bool(forKey: "shouldShowNBA") ?? false,
            "shouldShowSoccer": defaults?.bool(forKey: "shouldShowSoccer") ?? false,
            "shouldShowNHL": defaults?.bool(forKey: "shouldShowNHL") ?? false,
            "shouldShowMLB": defaults?.bool(forKey: "shouldShowMLB") ?? false,
            "shouldShowNFL": defaults?.bool(forKey: "shouldShowNFL") ?? false,
            "shouldShowGolf": defaults?.bool(forKey: "shouldShowGolf") ?? false,
            "shouldShowTennis": defaults?.bool(forKey: "shouldShowTennis") ?? false,
            "shouldShowRacing": defaults?.bool(forKey: "shouldShowRacing") ?? false,
            "favoritesOnlyNBA": defaults?.bool(forKey: "favoritesOnlyNBA") ?? false,
            "favoritesOnlySoccer": defaults?.bool(forKey: "favoritesOnlySoccer") ?? false,
            "favoritesOnlyNHL": defaults?.bool(forKey: "favoritesOnlyNHL") ?? false,
            "favoritesOnlyMLB": defaults?.bool(forKey: "favoritesOnlyMLB") ?? false,
            "favoritesOnlyNFL": defaults?.bool(forKey: "favoritesOnlyNFL") ?? false,
            "favoritesOnlyGolf": defaults?.bool(forKey: "favoritesOnlyGolf") ?? false,
            "favoritesOnlyTennis": defaults?.bool(forKey: "favoritesOnlyTennis") ?? false,
            "favoritesOnlyRacing": defaults?.bool(forKey: "favoritesOnlyRacing") ?? false,
            "favorites": favorites,
            "hiddenCompetitions": hidden,
        ]

        try? WCSession.default.updateApplicationContext(context)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            syncAllPreferences()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    // Receive favorites changes from Watch
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = message["action"] as? String else { return }

        if action == "updateFavorites", let favorites = message["favorites"] as? [String] {
            let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
            defaults?.set(favorites, forKey: "Favorites")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
            }
        }
    }
}
#endif
