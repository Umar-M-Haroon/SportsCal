//
//  WatchGameRow.swift
//  SportsCalWatch
//
//  Compact game row for team sports on Apple Watch.
//  Text abbreviations only — no badge images (more legible at 40mm, saves memory).
//

import SwiftUI
import SportsCalModel

struct WatchGameRow: View {
    let game: Game
    let teams: [Team]
    let isFavorite: Bool

    var body: some View {
        NavigationLink(value: game) {
            HStack(spacing: 6) {
                sportIcon
                VStack(alignment: .leading, spacing: 2) {
                    if isLive {
                        liveContent
                    } else if game.isCompleted == true {
                        finalContent
                    } else {
                        upcomingContent
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Sport Icon

    private var sportIcon: some View {
        Group {
            if let sportType = game.sportType {
                Image(systemName: sportType.widgetSystemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(sportType.widgetColor)
                    .frame(width: 16)
            }
        }
    }

    // MARK: - Live Game

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(awayAbbr)
                    .font(.system(size: 13, weight: isFavorite && favoriteTeams.contains(game.strAwayTeam) ? .bold : .regular))
                Spacer()
                Text(game.intAwayScore ?? "0")
                    .font(.system(size: 13, weight: .semibold))
            }
            HStack(spacing: 4) {
                Text(homeAbbr)
                    .font(.system(size: 13, weight: isFavorite && favoriteTeams.contains(game.strHomeTeam) ? .bold : .regular))
                Spacer()
                Text(game.intHomeScore ?? "0")
                    .font(.system(size: 13, weight: .semibold))
            }
            if let progress = game.displayStatus {
                Text(progress)
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Final Score

    private var finalContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(awayAbbr)
                    .font(.system(size: 13))
                Spacer()
                Text(game.intAwayScore ?? "0")
                    .font(.system(size: 13, weight: .semibold))
            }
            HStack(spacing: 4) {
                Text(homeAbbr)
                    .font(.system(size: 13))
                Spacer()
                Text(game.intHomeScore ?? "0")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("Final")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Upcoming Game

    private var upcomingContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(awayAbbr) @ \(homeAbbr)")
                .font(.system(size: 13, weight: isFavorite ? .semibold : .regular))
            if let date = game.standardDate {
                Text(date, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var isLive: Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty &&
               status != "ft" && status != "aet" &&
               status != "not started" && status != "ns" &&
               game.intHomeScore != nil && game.intAwayScore != nil
    }

    private var homeAbbr: String {
        abbreviation(teamID: game.idHomeTeam, name: game.strHomeTeam)
    }

    private var awayAbbr: String {
        abbreviation(teamID: game.idAwayTeam, name: game.strAwayTeam)
    }

    private var favoriteTeams: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "Favorites") ?? [])
    }

    private func abbreviation(teamID: String?, name: String) -> String {
        if let team = Team.getTeamInfoFrom(teams: teams, teamID: teamID, teamName: name),
           let short = team.strTeamShort {
            return short
        }
        return Team.shortCode(strTeamShort: nil, name: name)
    }
}
