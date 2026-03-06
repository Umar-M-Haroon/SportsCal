//
//  UserDefaultStorage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/14/21.
//

import Foundation
import SwiftUI
import SportsCalModel

@Observable
class UserDefaultStorage {
    @ObservationIgnored @AppStorage("shouldShowNBA") var shouldShowNBA: Bool = false
    @ObservationIgnored @AppStorage("shouldShowNFL") var shouldShowNFL: Bool = false
    @ObservationIgnored @AppStorage("shouldShowNHL") var shouldShowNHL: Bool = false
    @ObservationIgnored @AppStorage("shouldShowSoccer") var shouldShowSoccer: Bool = false
    @ObservationIgnored @AppStorage("shouldShowMLB") var shouldShowMLB: Bool = false
    @ObservationIgnored @AppStorage("shouldShowGolf") var shouldShowGolf: Bool = false
    @ObservationIgnored @AppStorage("shouldShowTennis") var shouldShowTennis: Bool = false
    @ObservationIgnored @AppStorage("shouldShowRacing") var shouldShowRacing: Bool = false
    @ObservationIgnored @AppStorage("shouldShowOnboarding") var shouldShowOnboarding: Bool = true
    @ObservationIgnored @AppStorage("hidesPastEvents") var hidePastEvents: Bool = true  // Hide past games by default for performance
    @ObservationIgnored @AppStorage("soonestOnTop") var soonestOnTop: Bool = true
    @ObservationIgnored @AppStorage("duration") var durations: Durations = .twoWeeks  // Show 2 weeks ahead (reasonable default)
    @ObservationIgnored @AppStorage("launches") var launches: Int = 0
    @ObservationIgnored @AppStorage("dateFormat") var dateFormat: Int = 1
    @ObservationIgnored @AppStorage("hidePastGamesDuration") var hidePastGamesDuration: Durations = .oneWeek  // When enabled, show past week
    @ObservationIgnored @AppStorage("showStartTime") var showStartTime: Bool = true
    @ObservationIgnored @AppStorage("debugMode") var debugMode: Bool = false
    @ObservationIgnored @AppStorage("hiddenCompetitions") var hiddenCompetitions: [String] = []
    @ObservationIgnored @AppStorage("useRelativeValue") var useRelativeValue: Bool = false
    @ObservationIgnored @AppStorage("autoFollowFavorites") var autoFollowFavorites: Bool = true
    @ObservationIgnored @AppStorage("useLocalServer") var useLocalServer: Bool = true

    // MARK: - Auto-Follow Event IDs
    private static let autoFollowKey = "autoFollowEventIDs"
    private static let suiteName = "group.Komodo.SportsCal"

    var autoFollowEventIDs: Set<String> {
        get {
            let array = UserDefaults(suiteName: Self.suiteName)?.stringArray(forKey: Self.autoFollowKey) ?? []
            return Set(array)
        }
        set {
            UserDefaults(suiteName: Self.suiteName)?.set(Array(newValue), forKey: Self.autoFollowKey)
        }
    }

    func addAutoFollow(_ eventID: String) {
        var ids = autoFollowEventIDs
        ids.insert(eventID)
        autoFollowEventIDs = ids
    }

    func removeAutoFollow(_ eventID: String) {
        var ids = autoFollowEventIDs
        ids.remove(eventID)
        autoFollowEventIDs = ids
    }

    func isAutoFollowing(_ eventID: String) -> Bool {
        autoFollowEventIDs.contains(eventID)
    }

    /// Remove auto-follow entries for games whose dates are in the past,
    /// and debug fake game IDs that no longer exist in the game list.
    func cleanupExpiredAutoFollows(games: [Game]) {
        let now = Date()
        let gameIDs = Set(games.compactMap(\.idEvent))
        let expired = autoFollowEventIDs.filter { eventID in
            // Remove debug fake IDs that are no longer in the game list
            if eventID.hasPrefix("debug-fake-") && !gameIDs.contains(eventID) {
                return true
            }
            guard let game = games.first(where: { $0.idEvent == eventID }),
                  let date = game.standardDate else { return false }
            return date < now
        }
        if !expired.isEmpty {
            var ids = autoFollowEventIDs
            for id in expired { ids.remove(id) }
            autoFollowEventIDs = ids
        }
    }

    // Stored property tracked by @Observable so chip filters react to changes
    var enabledSports: [SportType] = []

    // MARK: - Focus Filter

    /// Whether a Focus Filter is currently overriding sport preferences.
    var focusFilterActive: Bool {
        UserDefaults(suiteName: Self.suiteName)?.bool(forKey: "focusFilterActive") ?? false
    }

    /// Returns the effective "should show" value for a sport, respecting Focus Filter overrides.
    func effectiveShouldShow(_ sport: SportType) -> Bool {
        if focusFilterActive {
            let defaults = UserDefaults(suiteName: Self.suiteName)
            switch sport {
            case .basketball: return defaults?.bool(forKey: "focus_shouldShowNBA") ?? true
            case .soccer:     return defaults?.bool(forKey: "focus_shouldShowSoccer") ?? true
            case .hockey:     return defaults?.bool(forKey: "focus_shouldShowNHL") ?? true
            case .mlb:        return defaults?.bool(forKey: "focus_shouldShowMLB") ?? true
            case .nfl:        return defaults?.bool(forKey: "focus_shouldShowNFL") ?? true
            case .golf:       return defaults?.bool(forKey: "focus_shouldShowGolf") ?? true
            case .tennis:     return defaults?.bool(forKey: "focus_shouldShowTennis") ?? true
            case .racing:     return defaults?.bool(forKey: "focus_shouldShowRacing") ?? true
            }
        }
        switch sport {
        case .basketball: return shouldShowNBA
        case .soccer:     return shouldShowSoccer
        case .hockey:     return shouldShowNHL
        case .mlb:        return shouldShowMLB
        case .nfl:        return shouldShowNFL
        case .golf:       return shouldShowGolf
        case .tennis:     return shouldShowTennis
        case .racing:     return shouldShowRacing
        }
    }

    /// Clears Focus Filter overrides (called when no Focus is active).
    func clearFocusFilter() {
        let defaults = UserDefaults(suiteName: Self.suiteName)
        defaults?.set(false, forKey: "focusFilterActive")
    }

    init() {
        recomputeEnabledSports()
    }

    func recomputeEnabledSports() {
        var sports: [SportType] = []
        if effectiveShouldShow(.basketball) { sports.append(.basketball) }
        if effectiveShouldShow(.soccer)     { sports.append(.soccer) }
        if effectiveShouldShow(.hockey)     { sports.append(.hockey) }
        if effectiveShouldShow(.mlb)        { sports.append(.mlb) }
        if effectiveShouldShow(.nfl)        { sports.append(.nfl) }
        if effectiveShouldShow(.golf)       { sports.append(.golf) }
        if effectiveShouldShow(.tennis)     { sports.append(.tennis) }
        if effectiveShouldShow(.racing)     { sports.append(.racing) }
        enabledSports = sports
        syncSportPrefsToAppGroup()
    }

    /// Mirror sport preference flags to the shared app group so widgets can read them
    private func syncSportPrefsToAppGroup() {
        let defaults = UserDefaults(suiteName: Self.suiteName)
        defaults?.set(shouldShowNBA, forKey: "shouldShowNBA")
        defaults?.set(shouldShowNFL, forKey: "shouldShowNFL")
        defaults?.set(shouldShowNHL, forKey: "shouldShowNHL")
        defaults?.set(shouldShowSoccer, forKey: "shouldShowSoccer")
        defaults?.set(shouldShowMLB, forKey: "shouldShowMLB")
        defaults?.set(shouldShowGolf, forKey: "shouldShowGolf")
        defaults?.set(shouldShowTennis, forKey: "shouldShowTennis")
        defaults?.set(shouldShowRacing, forKey: "shouldShowRacing")
        defaults?.set(hiddenCompetitions, forKey: "hiddenCompetitions")
    }

    /// Sync just hiddenCompetitions to the shared app group (called from CompetitionView)
    func syncHiddenCompetitions() {
        let defaults = UserDefaults(suiteName: Self.suiteName)
        defaults?.set(hiddenCompetitions, forKey: "hiddenCompetitions")
    }

    func toggleSport(_ sport: SportType, enabled: Bool) {
        switch sport {
        case .basketball: shouldShowNBA = enabled
        case .soccer:     shouldShowSoccer = enabled
        case .hockey:     shouldShowNHL = enabled
        case .mlb:        shouldShowMLB = enabled
        case .nfl:        shouldShowNFL = enabled
        case .golf:       shouldShowGolf = enabled
        case .tennis:     shouldShowTennis = enabled
        case .racing:     shouldShowRacing = enabled
        }
        recomputeEnabledSports()
    }

    func switchTo(sportType: SportType) {
        shouldShowNFL = false
        shouldShowNBA = false
        shouldShowNHL = false
        shouldShowSoccer = false
        shouldShowMLB = false
        shouldShowGolf = false
        shouldShowTennis = false
        shouldShowRacing = false
        switch sportType {
        case .hockey:
            shouldShowNHL = true
        case .nfl:
            shouldShowNFL = true
        case .basketball:
            shouldShowNBA = true
        case .mlb:
            shouldShowMLB = true
        case .soccer:
            shouldShowSoccer = true
        case .golf:
            shouldShowGolf = true
        case .tennis:
            shouldShowTennis = true
        case .racing:
            shouldShowRacing = true
        }
        recomputeEnabledSports()
    }
}
extension Array: @retroactive RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }
    
    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}
