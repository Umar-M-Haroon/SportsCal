//
//  WhatsNew.swift
//  SportsCal
//
//  The "What's New" sheet shown once to upgrading users after an update. Each
//  release lists its features, and a feature can carry a one-tap CTA (turn on a
//  league, enable a sport, open Manage Sports) so users can act without digging
//  through Settings.
//
//  To ship notes for a new version: add a `WhatsNewRelease` at the top of
//  `WhatsNewRelease.all`. Fresh installs never see it (onboarding covers them),
//  and a user who skips versions sees only the newest release.
//

import SwiftUI
import SportsCalModel

// MARK: - Content

struct WhatsNewRelease: Identifiable {
    /// Marketing version these notes ship with, e.g. "3.3". Shown to anyone whose
    /// app version is at or above it and who hasn't seen it yet.
    let version: String
    let features: [WhatsNewFeature]

    var id: String { version }
}

struct WhatsNewFeature: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var action: WhatsNewAction? = nil
}

/// A one-tap call to action attached to a feature.
enum WhatsNewAction: Hashable {
    /// Unhide a competition and make sure its sport is on.
    case showCompetition(Leagues, sport: SportType)
    /// Turn a whole sport on.
    case enableSport(SportType)
    /// Open Manage Sports (sport toggles, per-sport leagues, tennis/golf coverage),
    /// with a button title that fits the feature.
    case manageSports(title: String)

    /// Button title before the action is taken.
    var title: String {
        switch self {
        case .showCompetition(let league, _): return "Turn On \(league.leagueName)"
        case .enableSport(let sport): return "Turn On \(sport.displayName)"
        case .manageSports(let title): return title
        }
    }

    /// Button title once the action's effect is already in place.
    var doneTitle: String {
        switch self {
        case .showCompetition(let league, _): return "\(league.leagueName) On"
        case .enableSport(let sport): return "\(sport.displayName) On"
        case .manageSports: return title
        }
    }

    /// Short label for telemetry.
    var telemetryName: String {
        switch self {
        case .showCompetition(let league, _): return "competition:\(league.leagueName)"
        case .enableSport(let sport): return "sport:\(sport.rawValue)"
        case .manageSports: return "manage_sports"
        }
    }
}

extension WhatsNewRelease {
    /// Newest first.
    static let all: [WhatsNewRelease] = [
        WhatsNewRelease(version: "3.3", features: [
            WhatsNewFeature(
                id: "a-league",
                title: "A-League",
                subtitle: "Fixtures, live scores, standings, and team widgets for Australia's top flight.",
                systemImage: "soccerball",
                tint: Color.app(.soccer),
                action: .showCompetition(.A_League, sport: .soccer)
            ),
            WhatsNewFeature(
                id: "tour-tiers",
                title: "Tennis & Golf Coverage",
                subtitle: "Just the Grand Slams and majors, the big events, or every tournament. Players you follow always show.",
                systemImage: "trophy.fill",
                tint: .orange,
                action: .manageSports(title: "Choose Coverage")
            ),
            WhatsNewFeature(
                id: "more-golf-tours",
                title: "More Golf Tours",
                subtitle: "DP World, LPGA, LIV, Champions, and Korn Ferry tours join the PGA TOUR.",
                systemImage: "figure.golf",
                tint: Color.app(.golf),
                action: .enableSport(.golf)
            ),
        ]),
    ]
}

// MARK: - Presentation policy

/// Pure decision logic, split out for unit tests.
enum WhatsNewPolicy {
    /// The release to show at launch, or nil.
    ///
    /// - `lastSeen == nil` means the user updated from a build that predates this
    ///   sheet, so they still get the current notes.
    /// - Fresh installs get onboarding instead and are marked as seen by the caller.
    static func releaseToShow(
        appVersion: String,
        lastSeen: String?,
        isFreshInstall: Bool,
        releases: [WhatsNewRelease] = WhatsNewRelease.all
    ) -> WhatsNewRelease? {
        guard !isFreshInstall, let release = latestRelease(for: appVersion, in: releases) else { return nil }
        if let lastSeen, compare(release.version, lastSeen) != .orderedDescending { return nil }
        return release
    }

    /// Newest release at or below `appVersion`, so a 3.3.1 hotfix still carries the
    /// 3.3 notes for anyone who skipped 3.3.
    static func latestRelease(for appVersion: String, in releases: [WhatsNewRelease] = WhatsNewRelease.all) -> WhatsNewRelease? {
        releases
            .filter { compare($0.version, appVersion) != .orderedDescending }
            .max { compare($0.version, $1.version) == .orderedAscending }
    }

    /// Numeric dotted-version compare where missing components count as 0 ("3.3" == "3.3.0").
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let r = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(l.count, r.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

// MARK: - Persistence

enum WhatsNewStore {
    private static let lastSeenKey = "whatsNewLastSeenVersion"
    /// Launch argument `-WhatsNewForce YES` shows the newest notes every launch, even
    /// before the version is bumped.
    private static let forceKey = "WhatsNewForce"

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Decides whether to show the sheet this launch. Fresh installs are marked seen
    /// here so they don't get it on their second launch.
    static func releaseForLaunch(isFreshInstall: Bool, defaults: UserDefaults = .standard) -> WhatsNewRelease? {
        if defaults.bool(forKey: forceKey) {
            return WhatsNewRelease.all.first
        }
        if isFreshInstall {
            markSeen(defaults: defaults)
            return nil
        }
        return WhatsNewPolicy.releaseToShow(
            appVersion: appVersion,
            lastSeen: defaults.string(forKey: lastSeenKey),
            isFreshInstall: false
        )
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(appVersion, forKey: lastSeenKey)
    }
}

// MARK: - Actions

extension WhatsNewAction {
    /// True when the action's effect is already in place, so the button shows its
    /// done state instead. Navigation actions are never "done".
    func isSatisfied(in storage: UserDefaultStorage) -> Bool {
        _ = storage.preferenceVersion
        switch self {
        case .showCompetition(let league, let sport):
            return storage.userShouldShow(sport) && !storage.hiddenCompetitions.contains(league.leagueName)
        case .enableSport(let sport):
            return storage.userShouldShow(sport)
        case .manageSports:
            return false
        }
    }

    /// Writes the preference change. Returns false for navigation actions, which
    /// change nothing and are handled by the sheet.
    @discardableResult
    func applyPreferences(storage: UserDefaultStorage) -> Bool {
        switch self {
        case .showCompetition(let league, let sport):
            storage.hiddenCompetitions.removeAll { $0 == league.leagueName }
            storage.syncHiddenCompetitions()
            if !storage.userShouldShow(sport) {
                storage.toggleSport(sport, enabled: true)
            }
            return true
        case .enableSport(let sport):
            storage.toggleSport(sport, enabled: true)
            return true
        case .manageSports:
            return false
        }
    }

    /// Applies a preference action and refetches so the newly visible games appear.
    @MainActor
    func apply(storage: UserDefaultStorage, viewModel: GameViewModel) {
        guard applyPreferences(storage: storage) else { return }
        viewModel.filterSports(force: true)
        viewModel.getInfo()
    }
}
