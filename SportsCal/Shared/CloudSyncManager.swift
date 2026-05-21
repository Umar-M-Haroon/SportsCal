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
        "shouldShowWNBA",
        "favoritesOnlyNBA", "favoritesOnlyNFL", "favoritesOnlyNHL", "favoritesOnlySoccer",
        "favoritesOnlyMLB", "favoritesOnlyGolf", "favoritesOnlyTennis", "favoritesOnlyRacing",
        "favoritesOnlyCompetitions",
        "hidesPastEvents", "soonestOnTop", "duration", "dateFormat",
        "hidePastGamesDuration", "showStartTime", "hiddenCompetitions",
        "useRelativeValue", "autoFollowFavorites", "showSuggestedForYou",
        "appTheme", "sportOrder",
        "Favorites", "FavoritePlayers"
    ]

    /// Keys whose values are stored in the shared app group (not standard defaults) on iOS/macOS.
    private let appGroupKeys: Set<String> = ["Favorites", "FavoritePlayers"]

    /// Subset of appGroupKeys whose payload became a dict in v2 of the Favorites schema
    /// (`{ schemaVersion, ids, legacy }`). All other appGroupKeys are still `[String]`.
    private let favoritesDictKey = "Favorites"

    private let timestampKey = "cloudSync_lastWriteTimestamp"

    /// Flag to prevent echo loops when applying remote changes locally.
    private var isApplyingRemote = false

    /// Called when remote preferences arrive (used by watchOS to reload WatchViewModel).
    var onRemoteUpdate: (() -> Void)?

    /// Posted on the main queue after CloudSyncManager applies a remote update to local
    /// UserDefaults. iOS/macOS app views listen to this to refilter games — the
    /// `@ObservationIgnored @AppStorage` properties on `UserDefaultStorage` don't drive
    /// view re-evaluation reliably, so an explicit notification is the cheapest fix.
    static let didApplyRemoteUpdateNotification = Notification.Name("cloudSyncDidApplyRemoteUpdate")

    /// Timestamp of the most recent successful local push (set after `pushAllToCloud`).
    private(set) var lastPushDate: Date?

    /// Timestamp of the most recent change received from another device.
    private(set) var lastRemoteUpdateDate: Date?

    /// Reason code from the most recent remote change notification.
    private(set) var lastRemoteChangeReason: Int?

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

        // Favorites are stored in the shared app-group suite on iOS/macOS, and
        // UserDefaults.didChangeNotification doesn't reliably fire for non-standard
        // suites — so observe the dedicated notification too. Use the raw name
        // because Favorites.swift isn't a member of every target that builds
        // CloudSyncManager.swift.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(favoritesDidChange),
            name: NSNotification.Name("favoritesDidChange"),
            object: nil
        )
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
        lastRemoteUpdateDate = Date()
        lastRemoteChangeReason = reason

        isApplyingRemote = true
        defer { isApplyingRemote = false }

        let defaults = UserDefaults.standard
        let isInitialSync = (reason == NSUbiquitousKeyValueStoreInitialSyncChange)

        for key in relevantKeys {
            let cloudValue = kvStore.object(forKey: key)

            if key == favoritesDictKey {
                applyFavoritesDict(cloudValue: cloudValue, unionMerge: isInitialSync)
            } else if appGroupKeys.contains(key) {
                applyFavoritesArray(forKey: key, cloudValue: cloudValue, unionMerge: isInitialSync)
            } else if let value = cloudValue {
                defaults.set(value, forKey: key)
            }
        }

        #if os(iOS)
        mirrorSportPrefsToAppGroup()
        #endif

        let favoritesChanged = relevantKeys.contains(where: { appGroupKeys.contains($0) })
        DispatchQueue.main.async { [weak self] in
            #if !os(watchOS)
            self?.storage?.recomputeEnabledSports()
            if favoritesChanged {
                self?.favorites?.reloadFromDefaults()
            }
            #endif
            NotificationCenter.default.post(name: Self.didApplyRemoteUpdateNotification, object: nil)
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

            if key == favoritesDictKey {
                applyFavoritesDict(cloudValue: cloudValue, unionMerge: initialSync)
            } else if appGroupKeys.contains(key) {
                applyFavoritesArray(forKey: key, cloudValue: cloudValue, unionMerge: initialSync)
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
            NotificationCenter.default.post(name: Self.didApplyRemoteUpdateNotification, object: nil)
            self?.onRemoteUpdate?()
        }

        logger.info("Pulled cloud preferences to local")
    }

    /// Apply a Favorites payload from iCloud. Tolerates both shapes:
    /// - v1 legacy: `[String]` of team names (devices that haven't yet shipped the ID migration)
    /// - v2 dict: `{ schemaVersion, ids: [String], legacy: [String] }`
    /// On union merge, ids and legacy entries are unioned independently.
    private func applyFavoritesDict(cloudValue: Any?, unionMerge: Bool) {
        let store = favoritesDefaults()
        let key = favoritesDictKey

        // Decode whatever shape arrived.
        let cloudIDs: Set<String>
        let cloudLegacy: Set<String>
        if let dict = cloudValue as? [String: Any] {
            cloudIDs = Set((dict["ids"] as? [String]) ?? [])
            cloudLegacy = Set((dict["legacy"] as? [String]) ?? [])
        } else if let array = cloudValue as? [String] {
            // Legacy device pushed a names array — treat as legacy entries to be
            // resolved locally on next TeamsManager refresh.
            cloudIDs = []
            cloudLegacy = Set(array)
        } else {
            return
        }

        // Decode local payload (same dual-shape tolerance).
        let localRaw = store?.object(forKey: key)
        var localIDs: Set<String> = []
        var localLegacy: Set<String> = []
        if let dict = localRaw as? [String: Any] {
            localIDs = Set((dict["ids"] as? [String]) ?? [])
            localLegacy = Set((dict["legacy"] as? [String]) ?? [])
        } else if let array = localRaw as? [String] {
            localLegacy = Set(array)
        }

        let mergedIDs: Set<String>
        let mergedLegacy: Set<String>
        if unionMerge {
            mergedIDs = localIDs.union(cloudIDs)
            mergedLegacy = localLegacy.union(cloudLegacy)
        } else {
            mergedIDs = cloudIDs
            mergedLegacy = cloudLegacy
        }

        let payload: [String: Any] = [
            "schemaVersion": 2,
            "ids": Array(mergedIDs),
            "legacy": Array(mergedLegacy)
        ]
        store?.set(payload, forKey: key)

        if unionMerge {
            // Push merged result back so other devices converge.
            kvStore.set(payload, forKey: key)
        }
    }

    private func applyFavoritesArray(forKey key: String, cloudValue: Any?, unionMerge: Bool) {
        guard let cloudArray = cloudValue as? [String] else { return }
        let store = favoritesDefaults()

        if unionMerge {
            // Merge: union of local + cloud
            let localArray = store?.stringArray(forKey: key) ?? []
            let merged = Array(Set(localArray).union(Set(cloudArray)))
            store?.set(merged, forKey: key)
            // Push merged result back to cloud so other devices converge
            kvStore.set(merged, forKey: key)
        } else {
            // Last-writer-wins
            store?.set(cloudArray, forKey: key)
        }
    }

    private func favoritesDefaults() -> UserDefaults? {
        #if os(watchOS)
        return UserDefaults.standard
        #else
        return UserDefaults(suiteName: "group.Komodo.SportsCal")
        #endif
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

    @objc private func favoritesDidChange() {
        guard !isApplyingRemote else { return }
        pushAllToCloud()
    }

    private func pushAllToCloud() {
        let defaults = UserDefaults.standard

        let groupStore = favoritesDefaults()
        for key in syncableKeys {
            if appGroupKeys.contains(key) {
                if let value = groupStore?.object(forKey: key) {
                    kvStore.set(value, forKey: key)
                }
            } else if let value = defaults.object(forKey: key) {
                kvStore.set(value, forKey: key)
            }
        }

        let now = Date()
        kvStore.set(now.timeIntervalSince1970, forKey: timestampKey)
        kvStore.synchronize()
        lastPushDate = now
    }

    // MARK: - Diagnostics

    struct Diagnostics {
        var bundleIdentifier: String
        var kvStoreIdentifier: String
        var iCloudAccountAvailable: Bool
        var lastPushDate: Date?
        var lastRemoteUpdateDate: Date?
        var lastRemoteChangeReason: Int?
        var cloudTimestamp: Date?
        var entries: [Entry]

        struct Entry: Identifiable, Hashable {
            var id: String { key }
            var key: String
            var localValue: String
            var cloudValue: String
            var inSync: Bool
        }
    }

    func currentDiagnostics() -> Diagnostics {
        kvStore.synchronize()
        let bundle = Bundle.main.bundleIdentifier ?? "(unknown)"
        let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        let cloudTs = kvStore.double(forKey: timestampKey)
        let cloudDate = cloudTs > 0 ? Date(timeIntervalSince1970: cloudTs) : nil

        let standard = UserDefaults.standard
        let group = favoritesDefaults()

        var entries: [Diagnostics.Entry] = []
        for key in syncableKeys.sorted() {
            let cloudVal = kvStore.object(forKey: key)
            let localVal: Any? = appGroupKeys.contains(key)
                ? group?.object(forKey: key)
                : standard.object(forKey: key)
            entries.append(.init(
                key: key,
                localValue: Self.describe(localVal),
                cloudValue: Self.describe(cloudVal),
                inSync: Self.equalDefaultsValues(localVal, cloudVal)
            ))
        }

        return Diagnostics(
            bundleIdentifier: bundle,
            kvStoreIdentifier: bundle,
            iCloudAccountAvailable: iCloudAvailable,
            lastPushDate: lastPushDate,
            lastRemoteUpdateDate: lastRemoteUpdateDate,
            lastRemoteChangeReason: lastRemoteChangeReason,
            cloudTimestamp: cloudDate,
            entries: entries
        )
    }

    /// Force-push every local syncable key to iCloud KVS.
    func forcePushAll() {
        pushAllToCloud()
    }

    /// Force-pull every cloud value into local UserDefaults (last-writer-wins; no merge).
    func forcePullAll() {
        kvStore.synchronize()
        pullAllFromCloud(initialSync: false)
    }

    private static func describe(_ value: Any?) -> String {
        guard let value else { return "—" }
        if let array = value as? [String] {
            if array.isEmpty { return "[]" }
            return "[" + array.joined(separator: ", ") + "]"
        }
        return String(describing: value)
    }

    private static func equalDefaultsValues(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (l?, r?):
            if let l = l as? [String], let r = r as? [String] {
                return Set(l) == Set(r)
            }
            return (l as? NSObject) == (r as? NSObject)
        default: return false
        }
    }

    // MARK: - App Group Mirroring (iOS only)

    #if os(iOS)
    private func mirrorSportPrefsToAppGroup() {
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        let standard = UserDefaults.standard
        let sportKeys = [
            "shouldShowNBA", "shouldShowNFL", "shouldShowNHL", "shouldShowSoccer",
            "shouldShowMLB", "shouldShowGolf", "shouldShowTennis", "shouldShowRacing",
            "shouldShowWNBA",
            "favoritesOnlyNBA", "favoritesOnlyNFL", "favoritesOnlyNHL", "favoritesOnlySoccer",
            "favoritesOnlyMLB", "favoritesOnlyGolf", "favoritesOnlyTennis", "favoritesOnlyRacing",
            "favoritesOnlyCompetitions",
            "hiddenCompetitions", "sportOrder"
        ]
        for key in sportKeys {
            defaults?.set(standard.object(forKey: key), forKey: key)
        }
    }
    #endif
}
