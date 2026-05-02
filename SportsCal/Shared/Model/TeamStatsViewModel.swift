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
    var teams: [NetworkHandler.TeamStatEntry] = []
    var availableStats: [String] = []
    var isLoading = false
    var error: String?

    func load(leagueID: Int) async {
        isLoading = true
        error = nil

        do {
            let decoded = try await NetworkHandler.getTeamStats(leagueID: leagueID)
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
