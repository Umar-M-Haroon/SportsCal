//
//  ScheduleSliceSync.swift
//  SportsCal
//
//  Fetches the schedule one sport at a time (`/schedules/sports/:key`), each slice
//  revalidated with its own ETag, instead of the all-sports `/schedules` blob.
//
//  The blob is ~29MB of JSON for everyone, and one sport's change invalidated all of
//  it. A fan of two sports now downloads those two, and a tennis final no longer
//  re-sends their NBA. Slices are merged back into one `LiveScore`, which stays the
//  on-disk cache and everything downstream, so nothing else changes shape.
//

import Foundation
import Synchronization
import SportsCalModel

enum ScheduleSliceSync {
    struct Outcome {
        /// The merged schedule for the wanted slices.
        let snapshot: LiveScore
        /// Validators for exactly the slices in `snapshot`.
        let etags: [LiveScore.WireKey: String]
        /// False when every slice was a 304 and the wanted set is the one on disk, so
        /// the cached snapshot is already this; nothing to apply or write.
        let changed: Bool
    }

    /// The slices to fetch. `sports` are the sports the user has on (their own choice,
    /// not a Focus override: the data should be there when the Focus ends);
    /// `favoriteKeys` the slices holding followed teams' games, kept even when that
    /// sport is off so favorites still show. Nothing on at all (mid-onboarding) means
    /// everything, as `/schedules` did.
    static func wantedKeys(sports: Set<SportType>, college: Bool, motorsport: Bool,
                           favoriteKeys: Set<LiveScore.WireKey>) -> [LiveScore.WireKey] {
        guard !sports.isEmpty else { return LiveScore.WireKey.allCases }
        var keys = Set(sports.flatMap { LiveScore.wireKeys(for: $0, college: college, motorsport: motorsport) })
        keys.formUnion(favoriteKeys)
        keys.insert(.meta)
        return LiveScore.WireKey.allCases.filter(keys.contains)
    }

    /// Sports the user has on, read straight from defaults (for the background refresh,
    /// where no `UserDefaultStorage` exists). Mirrors `UserDefaultStorage.userShouldShow`.
    static func enabledSports(defaults: UserDefaults = .standard) -> Set<SportType> {
        func on(_ key: String) -> Bool { defaults.bool(forKey: key) }
        var sports = Set<SportType>()
        if on("shouldShowNBA") || on("shouldShowWNBA") || on("shouldShowCBB") { sports.insert(.basketball) }
        // The World Cup rides in the soccer slice: turning it on pulls soccer in.
        if on("shouldShowSoccer") || on("shouldShowWorldCup") { sports.insert(.soccer) }
        if on("shouldShowNHL") { sports.insert(.hockey) }
        if on("shouldShowMLB") { sports.insert(.mlb) }
        if on("shouldShowNFL") || on("shouldShowCFB") { sports.insert(.nfl) }
        if on("shouldShowGolf") { sports.insert(.golf) }
        if on("shouldShowTennis") { sports.insert(.tennis) }
        if on("shouldShowRacing") { sports.insert(.racing) }
        if on("shouldShowCricket") { sports.insert(.cricket) }
        return sports
    }

    /// The wanted slices for the current preferences.
    static func currentWantedKeys(defaults: UserDefaults = .standard) -> [LiveScore.WireKey] {
        wantedKeys(sports: enabledSports(defaults: defaults),
                   college: NetworkHandler.wantsCollegeFootball,
                   motorsport: NetworkHandler.wantsMotorsportSeries,
                   favoriteKeys: FavoriteSlices.keys(defaults: defaults))
    }

    /// Revalidates each wanted slice against `cached` (the snapshot on disk) and merges
    /// the result. Nil when the server has no slice endpoint (an older server): the
    /// caller falls back to `/schedules`.
    static func refresh(wanted: [LiveScore.WireKey], cached: LiveScore?) async throws -> Outcome? {
        let base = NetworkHandler.baseURL()
        // A validator is only sent for a slice the cached snapshot actually holds.
        let stored = cached == nil ? [:] : SliceETagStore.etags(base: base)
        // The launch's requests may already be in flight (`LaunchPrefetch`); they count
        // only if they asked exactly this.
        let results: [LiveScore.WireKey: NetworkHandler.SliceFetchResult]
        if let prefetched = LaunchPrefetch.takeSlices(base: base, wanted: wanted, stored: stored) {
            results = try await prefetched.value
        } else {
            results = try await fetchSlices(wanted: wanted, stored: stored)
        }

        var parts: [LiveScore] = []
        var etags: [LiveScore.WireKey: String] = [:]
        var anyFresh = false
        for key in wanted {
            switch results[key] {
            case .unavailable, nil:
                return nil
            case .notModified:
                guard let cached else { throw URLError(.badServerResponse) }
                parts.append(cached.slice(key))
                etags[key] = stored[key]
            case .fresh(let slice, let etag):
                anyFresh = true
                parts.append(slice)
                if let etag { etags[key] = etag }
            }
        }
        let changed = anyFresh || Set(wanted) != Set(stored.keys)
        return Outcome(snapshot: LiveScore.combining(parts), etags: etags, changed: changed)
    }

    /// Every wanted slice, concurrently, revalidated with `stored`.
    static func fetchSlices(wanted: [LiveScore.WireKey], stored: [LiveScore.WireKey: String]) async throws
        -> [LiveScore.WireKey: NetworkHandler.SliceFetchResult] {
        try await withThrowingTaskGroup(of: (LiveScore.WireKey, NetworkHandler.SliceFetchResult).self) { group in
            for key in wanted {
                group.addTask { (key, try await NetworkHandler.fetchScheduleSlice(key, ifNoneMatch: stored[key])) }
            }
            var all: [LiveScore.WireKey: NetworkHandler.SliceFetchResult] = [:]
            for try await (key, result) in group { all[key] = result }
            return all
        }
    }
}

/// The launch's first requests (teams, the live snapshot, the schedule slices), sent the
/// moment the view model exists. Left to `getData` they waited for the main actor, which
/// is busy building the first frame for ~0.7-1.2s, and the schedule then waited behind
/// teams and live. Each is taken at most once, and only by a fetch asking exactly what
/// was prefetched (same server; for slices, the same keys and validators), so a changed
/// environment or a cache that failed to load just fetches normally.
enum LaunchPrefetch {
    private struct Slices {
        let wanted: [LiveScore.WireKey]
        let stored: [LiveScore.WireKey: String]
        let task: Task<[LiveScore.WireKey: NetworkHandler.SliceFetchResult], Error>
    }

    private struct State {
        let base: String
        var teams: Task<[Team], Error>?
        var live: Task<LiveScore, Error>?
        var slices: Slices?
    }

    private static let state = Mutex<State?>(nil)

    static func start() {
        let base = NetworkHandler.baseURL()
        let wanted = ScheduleSliceSync.currentWantedKeys()
        // What `refresh` will send if the cached snapshot loads; if it doesn't, the ETag
        // store is cleared first, the validators differ, and this goes unused.
        let stored = SliceETagStore.etags(base: base)
        let prefetch = State(
            base: base,
            teams: Task.detached(priority: .userInitiated) { try await NetworkHandler.getTeams() },
            live: Task.detached(priority: .userInitiated) { try await NetworkHandler.getLiveSnapshot() },
            slices: Slices(wanted: wanted, stored: stored, task: Task.detached(priority: .userInitiated) {
                try await ScheduleSliceSync.fetchSlices(wanted: wanted, stored: stored)
            })
        )
        state.withLock { $0 = prefetch }
    }

    static func takeTeams() -> Task<[Team], Error>? {
        state.withLock { state in
            guard state?.base == NetworkHandler.baseURL() else { return nil }
            defer { state?.teams = nil }
            return state?.teams
        }
    }

    static func takeLive() -> Task<LiveScore, Error>? {
        state.withLock { state in
            guard state?.base == NetworkHandler.baseURL() else { return nil }
            defer { state?.live = nil }
            return state?.live
        }
    }

    static func takeSlices(base: String, wanted: [LiveScore.WireKey], stored: [LiveScore.WireKey: String])
        -> Task<[LiveScore.WireKey: NetworkHandler.SliceFetchResult], Error>? {
        state.withLock { state in
            guard let slices = state?.slices, state?.base == base else { return nil }
            state?.slices = nil
            guard slices.wanted == wanted, slices.stored == stored else {
                slices.task.cancel()
                return nil
            }
            return slices.task
        }
    }
}

/// Per-slice ETags of the merged snapshot in the on-disk games cache, for one server.
///
/// Same invariant as `ScheduleETagStore`: an entry exists only while the snapshot on
/// disk holds that slice. Writers clear before replacing the cache file and store after
/// the atomic write lands; a missing cache clears everything.
enum SliceETagStore {
    private static let defaultsKey = "schedules.slices.etag.v1"
    private static var defaults: UserDefaults { .standard }

    static func etags(base: String) -> [LiveScore.WireKey: String] {
        guard let record = defaults.dictionary(forKey: defaultsKey) as? [String: String],
              record["base"] == base else { return [:] }
        var result: [LiveScore.WireKey: String] = [:]
        for (key, value) in record where key != "base" {
            if let wire = LiveScore.WireKey(rawValue: key) { result[wire] = value }
        }
        return result
    }

    static func store(_ etags: [LiveScore.WireKey: String], base: String) {
        var record = ["base": base]
        for (key, value) in etags { record[key.rawValue] = value }
        defaults.set(record, forKey: defaultsKey)
    }

    static func clear() {
        defaults.removeObject(forKey: defaultsKey)
    }
}

/// Slices holding followed teams' games, remembered between launches so a followed team
/// in a sport the user has switched off keeps showing. Recomputed from each snapshot the
/// app applies; the first one after updating is the old all-sports cache, which seeds it.
enum FavoriteSlices {
    private static let defaultsKey = "schedules.favoriteSlices.v1"

    static func keys(defaults: UserDefaults = .standard) -> Set<LiveScore.WireKey> {
        Set((defaults.stringArray(forKey: defaultsKey) ?? []).compactMap(LiveScore.WireKey.init(rawValue:)))
    }

    /// Records the slices of `snapshot` that contain a game `isFavorite` matches.
    /// A remembered slice that `snapshot` doesn't hold (or holds empty) is kept: there's
    /// no evidence the followed team left it.
    static func update(from snapshot: LiveScore, isFavorite: (Game) -> Bool, defaults: UserDefaults = .standard) {
        let previous = keys(defaults: defaults)
        let keys = LiveScore.WireKey.allCases.filter { key in
            guard key != .meta else { return false }
            let games = snapshot.slice(key).allGamesBySport.flatMap(\.games)
            if games.isEmpty { return previous.contains(key) }
            return games.contains(where: isFavorite)
        }
        defaults.set(keys.map(\.rawValue), forKey: defaultsKey)
    }
}
