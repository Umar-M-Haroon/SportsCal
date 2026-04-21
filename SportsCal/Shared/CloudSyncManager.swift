//
//  CloudSyncManager.swift
//  SportsCal
//
//  Bridges UserDefaults ↔ iCloud Key-Value Store for cross-device preference sync.
//

import Foundation
import os

final class CloudSyncManager {
    static let shared = CloudSyncManager()

    private let kvStore = NSUbiquitousKeyValueStore.default
    private let logger = Logger(subsystem: "com.KomodoLLC.SportsCal", category: "CloudSync")

    /// Keys that should be synced to iCloud KVS (maps 1:1 with UserDefaults keys).
    private let syncableKeys: Set<String> = [
        "shouldShowNBA", "shouldShowNFL", "shouldShowNHL", "shouldShowSoccer",
        "shouldShowMLB", "shouldShowGolf", "shouldShowTennis", "shouldShowRacing",
        "favoritesOnlyNBA", "favoritesOnlyNFL", "favoritesOnlyNHL", "favoritesOnlySoccer",
        "favoritesOnlyMLB", "favoritesOnlyGolf", "favoritesOnlyTennis", "favoritesOnlyRacing",
        "hidesPastEvents", "soonestOnTop", "duration", "dateFormat",
        "hidePastGamesDuration", "showStartTime", "hiddenCompetitions",
        "useRelativeValue", "autoFollowFavorites", "sportOrder", "Favorites"
    ]

    private let timestampKey = "cloudSync_lastWriteTimestamp"

    /// Flag to prevent echo loops when applying remote changes locally.
    private var isApplyingRemote = false

    /// Called when remote preferences arrive (used by watchOS to reload WatchViewModel).
    var onRemoteUpdate: (() -> Void)?

    #if !os(watchOS)
    private weak var storage: UserDefaultStorage?
    private weak var favorites: Favorites?
    #endif

    private init() {}

    // MARK: - Public

    #if !os(watchOS)
    func startSync(storage: UserDefaultStorage?, favorites: Favorites?) {
        self.storage = storage
        self.favorites = favorites
        performInitialSync()
    }
    #endif

    func startSync() {
        performInitialSync()
    }

    private func performInitialSync() {
        // Pull initial cloud state
        kvStore.synchronize()

        let cloudTimestamp = kvStore.double(forKey: timestampKey)
        if cloudTimestamp > 0 {
            // Cloud has data — pull cloud → local
            pullAllFromCloud(initialSync: true)
        } else {
            // Cloud is empty — push local → cloud
            pushAllToCloud()
        }

        // Observe remote changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore
        )

        // Observe local changes
        observeLocalChanges()
    }

    // MARK: - Cloud → Local (Pull)

    @objc private func cloudDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
              let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        else { return }

        let relevantKeys = changedKeys.filter { syncableKeys.contains($0) }
        guard !relevantKeys.isEmpty else { return }

        logger.info("Cloud change (reason \(reason)): \(relevantKeys)")

        isApplyingRemote = true
        defer { isApplyingRemote = false }

        let defaults = UserDefaults.standard
        let isInitialSync = (reason == NSUbiquitousKeyValueStoreInitialSyncChange)

        for key in relevantKeys {
            let cloudValue = kvStore.object(forKey: key)

            if key == "Favorites" {
                applyFavorites(cloudValue: cloudValue, unionMerge: isInitialSync)
            } else if let value = cloudValue {
                defaults.set(value, forKey: key)
            }
        }

        #if os(iOS)
        mirrorSportPrefsToAppGroup()
        #endif

        DispatchQueue.main.async { [weak self] in
            #if !os(watchOS)
            self?.storage?.recomputeEnabledSports()
            if relevantKeys.contains("Favorites") {
                self?.favorites?.reloadFromDefaults()
            }
            #endif
            self?.onRemoteUpdate?()
        }
    }

    private func pullAllFromCloud(initialSync: Bool) {
        isApplyingRemote = true
        defer { isApplyingRemote = false }

        let defaults = UserDefaults.standard
        let cloudDict = kvStore.dictionaryRepresentation

        for key in syncableKeys {
            guard let cloudValue = cloudDict[key] else { continue }

            if key == "Favorites" {
                applyFavorites(cloudValue: cloudValue, unionMerge: initialSync)
            } else {
                defaults.set(cloudValue, forKey: key)
            }
        }

        #if os(iOS)
        mirrorSportPrefsToAppGroup()
        #endif

        DispatchQueue.main.async { [weak self] in
            #if !os(watchOS)
            self?.storage?.recomputeEnabledSports()
            self?.favorites?.reloadFromDefaults()
            #endif
            self?.onRemoteUpdate?()
        }

        logger.info("Pulled cloud preferences to local")
    }

    private func applyFavorites(cloudValue: Any?, unionMerge: Bool) {
        guard let cloudArray = cloudValue as? [String] else { return }
        let cloudSet = Set(cloudArray)

        if unionMerge {
            // Merge: union of local + cloud
            #if os(watchOS)
            let localArray = UserDefaults.standard.stringArray(forKey: "Favorites") ?? []
            #else
            let localArray = UserDefaults(suiteName: "group.Komodo.SportsCal")?.stringArray(forKey: "Favorites") ?? []
            #endif
            let merged = Array(Set(localArray).union(cloudSet))
            #if os(watchOS)
            UserDefaults.standard.set(merged, forKey: "Favorites")
            #else
            UserDefaults(suiteName: "group.Komodo.SportsCal")?.set(merged, forKey: "Favorites")
            #endif
            // Also push merged result back to cloud
            kvStore.set(merged, forKey: "Favorites")
        } else {
            // Last-writer-wins
            #if os(watchOS)
            UserDefaults.standard.set(cloudArray, forKey: "Favorites")
            #else
            UserDefaults(suiteName: "group.Komodo.SportsCal")?.set(cloudArray, forKey: "Favorites")
            #endif
        }
    }

    // MARK: - Local → Cloud (Push)

    private func observeLocalChanges() {
        // Use NotificationCenter for UserDefaults changes (reliable for @AppStorage)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func userDefaultsDidChange() {
        guard !isApplyingRemote else { return }
        pushAllToCloud()
    }

    private func pushAllToCloud() {
        let defaults = UserDefaults.standard

        for key in syncableKeys {
            if key == "Favorites" {
                // Read favorites from the correct store
                #if os(watchOS)
                let value = defaults.object(forKey: key)
                #else
                let value = UserDefaults(suiteName: "group.Komodo.SportsCal")?.object(forKey: key)
                #endif
                if let value { kvStore.set(value, forKey: key) }
            } else if let value = defaults.object(forKey: key) {
                kvStore.set(value, forKey: key)
            }
        }

        kvStore.set(Date().timeIntervalSince1970, forKey: timestampKey)
        kvStore.synchronize()
    }

    // MARK: - App Group Mirroring (iOS only)

    #if os(iOS)
    private func mirrorSportPrefsToAppGroup() {
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        let standard = UserDefaults.standard
        let sportKeys = [
            "shouldShowNBA", "shouldShowNFL", "shouldShowNHL", "shouldShowSoccer",
            "shouldShowMLB", "shouldShowGolf", "shouldShowTennis", "shouldShowRacing",
            "favoritesOnlyNBA", "favoritesOnlyNFL", "favoritesOnlyNHL", "favoritesOnlySoccer",
            "favoritesOnlyMLB", "favoritesOnlyGolf", "favoritesOnlyTennis", "favoritesOnlyRacing",
            "hiddenCompetitions"
        ]
        for key in sportKeys {
            defaults?.set(standard.object(forKey: key), forKey: key)
        }
    }
    #endif
}
