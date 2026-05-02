//
//  StandingsViewModel.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/16/26.
//

import Foundation
import SportsCalModel

/// Fetches standings history from the server for the standings movement chart.
@MainActor
@Observable
class StandingsViewModel {
    var snapshots: [NetworkHandler.StandingsHistoryDay] = []
    var isLoading = false
    var error: String?

    func loadHistory(leagueID: Int, days: Int = 30) async {
        isLoading = true
        error = nil

        do {
            snapshots = try await NetworkHandler.getStandingsHistory(leagueID: leagueID, days: days)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
