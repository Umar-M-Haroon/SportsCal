//
//  TeamStatsViewModel.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/16/26.
//

import Foundation
import SportsCalModel

/// Fetches team stats from the server for the scatter plot.
@MainActor
@Observable
class TeamStatsViewModel {
    var teams: [TeamStatEntry] = []
    var availableStats: [String] = []
    var isLoading = false
    var error: String?

    struct TeamStatEntry: Codable, Identifiable {
        var id: String { teamName }
        let teamName: String
        let teamAbbreviation: String
        let teamColor: String
        let teamLogo: String
        let division: String
        let stats: [String: String]

        func statValue(_ name: String) -> Double? {
            guard let str = stats[name] else { return nil }
            return Double(str)
        }
    }

    func load(leagueID: Int) async {
        isLoading = true
        error = nil

        do {
            let baseURL = NetworkHandler.baseURL(debug: false)
            guard let url = URL(string: "\(baseURL)/stats/\(leagueID)/teams") else {
                error = "Invalid URL"
                isLoading = false
                return
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([TeamStatEntry].self, from: data)
            teams = decoded

            // Collect all available stat names
            var statNames = Set<String>()
            for team in decoded {
                for key in team.stats.keys {
                    if let _ = Double(team.stats[key] ?? "") {
                        statNames.insert(key)
                    }
                }
            }
            availableStats = statNames.sorted()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
