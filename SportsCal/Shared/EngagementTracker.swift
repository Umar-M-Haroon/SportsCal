//
//  EngagementTracker.swift
//  SportsCal (iOS)
//
//  Created by Claude on 3/23/26.
//

import Foundation
import SwiftUI
import SportsCalModel

struct TeamEngagement: Codable {
    var teamName: String
    var viewCount: Int
    var lastViewedDate: Date
    var sportRawValue: String
}

@Observable
class EngagementTracker {
    private(set) var engagements: [String: TeamEngagement]

    private let saveKey = "TeamEngagement"
    private let maxTracked = 20
    private let pruneThreshold = 0.5
    private let suggestionThreshold = 4.0
    private let decayHalfLife = 14.0

    init() {
        #if os(watchOS)
        let defaults = UserDefaults.standard
        #else
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        #endif
        if let data = defaults?.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([String: TeamEngagement].self, from: data) {
            engagements = decoded
        } else {
            engagements = [:]
        }
    }

    func recordView(team: String, sport: SportType) {
        var entry = engagements[team] ?? TeamEngagement(
            teamName: team,
            viewCount: 0,
            lastViewedDate: Date(),
            sportRawValue: sport.rawValue
        )
        entry.viewCount += 1
        entry.lastViewedDate = Date()
        engagements[team] = entry

        prune()
        save()
    }

    func suggestedTeamNames(excluding favorites: Set<String>) -> Set<String> {
        let now = Date()
        var result = Set<String>()
        for (name, entry) in engagements {
            guard !favorites.contains(name) else { continue }
            if decayedScore(entry: entry, now: now) >= suggestionThreshold {
                result.insert(name)
            }
        }
        return result
    }

    func topSuggestedTeam(excluding favorites: Set<String>) -> TeamEngagement? {
        let now = Date()
        return engagements.values
            .filter { !favorites.contains($0.teamName) }
            .filter { decayedScore(entry: $0, now: now) >= suggestionThreshold }
            .max { decayedScore(entry: $0, now: now) < decayedScore(entry: $1, now: now) }
    }

    private func decayedScore(entry: TeamEngagement, now: Date) -> Double {
        let daysSince = max(0, now.timeIntervalSince(entry.lastViewedDate) / 86400)
        return Double(entry.viewCount) * exp(-daysSince / decayHalfLife)
    }

    private func prune() {
        let now = Date()
        engagements = engagements.filter { _, entry in
            decayedScore(entry: entry, now: now) >= pruneThreshold
        }
        // Cap at maxTracked by removing lowest-scored entries
        if engagements.count > maxTracked {
            let sorted = engagements.sorted { decayedScore(entry: $0.value, now: now) > decayedScore(entry: $1.value, now: now) }
            engagements = Dictionary(uniqueKeysWithValues: sorted.prefix(maxTracked).map { ($0.key, $0.value) })
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(engagements) else { return }
        #if os(watchOS)
        UserDefaults.standard.set(data, forKey: saveKey)
        #else
        UserDefaults(suiteName: "group.Komodo.SportsCal")?.set(data, forKey: saveKey)
        #endif
    }
}
