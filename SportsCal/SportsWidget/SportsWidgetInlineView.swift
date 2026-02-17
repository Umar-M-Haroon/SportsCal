//
//  SportsWidgetInlineView.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 12/7/22.
//

import SwiftUI
import SportsCalModel

struct SportsWidgetInlineView: View {
    var entry: Provider.Entry

    var body: some View {
        if let displayText = getDisplayText() {
            Text(displayText)
                .font(.caption)
        } else {
            Text("No upcoming games")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// Gets the display text for the inline widget
    /// Priority: 1. Favorite team's live game, 2. Any live game, 3. Favorite team's upcoming game, 4. Any upcoming game
    private func getDisplayText() -> String? {
        guard let games = entry.game, !games.isEmpty else { return nil }

        let favorites = Favorites()

        // First priority: Favorite team's live game
        if let favoriteLiveGame = games.first(where: { game in
            isLiveGame(game) && favorites.contains(game)
        }) {
            return formatGame(favoriteLiveGame, live: true)
        }

        // Second priority: Any live game
        if let liveGame = games.first(where: { isLiveGame($0) }) {
            return formatGame(liveGame, live: true)
        }

        // Third priority: Favorite team's upcoming game
        if let favoriteUpcoming = games.first(where: { favorites.contains($0) }) {
            return formatGame(favoriteUpcoming, live: false)
        }

        // Fourth priority: Any upcoming game
        if let upcoming = games.first {
            return formatGame(upcoming, live: false)
        }

        return nil
    }

    private func formatGame(_ game: Game, live: Bool) -> String {
        // Individual sport formatting
        if game.isRace {
            let name = game.strHomeTeam
            if live, let leader = game.resolvedLeaderboard.first {
                return "\(name) \u{2022} \(leader.name) P\(leader.position)"
            }
            return formatUpcomingIndividual(game)
        }

        if game.isIndividualSport {
            let name = game.strHomeTeam
            if live, let leader = game.resolvedLeaderboard.first {
                return "\(name) \u{2022} \(leader.name) \(leader.score)"
            }
            return formatUpcomingIndividual(game)
        }

        // Team sport formatting
        if live {
            return formatLiveGame(game)
        }
        return formatUpcomingGame(game)
    }

    private func formatUpcomingIndividual(_ game: Game) -> String {
        var timeString = ""
        if let gameDate = game.standardDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            timeString = " \(formatter.string(from: gameDate))"
        }
        return "\(game.strHomeTeam)\(timeString)"
    }

    private func isLiveGame(_ game: Game) -> Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty &&
               status != "ft" &&
               status != "aet" &&
               status != "not started" &&
               status != "ns" &&
               game.intHomeScore != nil &&
               game.intAwayScore != nil
    }

    private func formatLiveGame(_ game: Game) -> String {
        let homeTeam = getTeamAbbreviation(teamID: game.idHomeTeam, teamName: game.strHomeTeam)
        let awayTeam = getTeamAbbreviation(teamID: game.idAwayTeam, teamName: game.strAwayTeam)
        let homeScore = game.intHomeScore ?? "0"
        let awayScore = game.intAwayScore ?? "0"
        let progress = game.strProgress ?? game.strStatus ?? ""

        return "\(awayTeam) \(awayScore) - \(homeTeam) \(homeScore) \(progress)"
    }

    private func formatUpcomingGame(_ game: Game) -> String {
        let homeTeam = getTeamAbbreviation(teamID: game.idHomeTeam, teamName: game.strHomeTeam)
        let awayTeam = getTeamAbbreviation(teamID: game.idAwayTeam, teamName: game.strAwayTeam)

        var timeString = ""
        if let gameDate = game.standardDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            timeString = formatter.string(from: gameDate)
        }

        return "\(awayTeam) @ \(homeTeam) \(timeString)"
    }

    private func getTeamAbbreviation(teamID: String?, teamName: String) -> String {
        if let id = teamID,
           let team = Team.getTeamInfoFrom(teams: entry.teams, teamID: id),
           let shortName = team.strTeamShort {
            return shortName
        }
        let name = teamName.trimmingCharacters(in: .whitespaces)
        if name.count >= 3 {
            return String(name.prefix(3)).uppercased()
        }
        return name.uppercased()
    }
}
