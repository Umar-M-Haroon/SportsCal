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
    var snapshots: [StandingsHistoryDay] = []
    var isLoading = false
    var error: String?

    struct StandingsHistoryDay: Codable, Identifiable {
        var id: String { date }
        let date: String
        let leagueID: Int
        let entries: [StandingsHistoryEntry]
    }

    struct StandingsHistoryEntry: Codable {
        let teamID: String?
        let teamName: String
        let teamAbbreviation: String?
        let teamColor: String?
        let teamLogo: String?
        let position: Int
        let division: String?
        let wins: Int?
        let losses: Int?
        let points: Int?
    }

    func loadHistory(leagueID: Int, days: Int = 30) async {
        isLoading = true
        error = nil

        do {
            let baseURL = NetworkHandler.baseURL(debug: false)
            guard let url = URL(string: "\(baseURL)/standings/\(leagueID)/history?days=\(days)") else {
                error = "Invalid URL"
                isLoading = false
                return
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([StandingsHistoryDay].self, from: data)
            snapshots = decoded
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
