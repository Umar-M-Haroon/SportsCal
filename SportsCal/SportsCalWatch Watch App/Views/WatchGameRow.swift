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
                    .foregroundStyle(WatchTokens.sport(sportType))
                    .frame(width: 16)
            }
        }
    }

    // MARK: - Live Game

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(awayAbbr)
                    .font(.system(size: 13, design: .rounded).weight(isFavorite && favoriteTeams.contains(game.strAwayTeam) ? .bold : .regular))
                Spacer()
                Text(game.intAwayScore ?? "0")
                    .font(.system(size: 13, design: .rounded).weight(.heavy))
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                Text(homeAbbr)
                    .font(.system(size: 13, design: .rounded).weight(isFavorite && favoriteTeams.contains(game.strHomeTeam) ? .bold : .regular))
                Spacer()
                Text(game.intHomeScore ?? "0")
                    .font(.system(size: 13, design: .rounded).weight(.heavy))
                    .monospacedDigit()
            }
            if let progress = game.displayStatus {
                WatchLiveTag(period: progress)
            }
        }
    }

    // MARK: - Final Score

    private var finalContent: some View {
        let homeWon = (Int(game.intHomeScore ?? "") ?? 0) > (Int(game.intAwayScore ?? "") ?? 0)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(awayAbbr)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(homeWon ? WatchTokens.inkSoft : WatchTokens.ink)
                Spacer()
                Text(game.intAwayScore ?? "0")
                    .font(.system(size: 13, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(homeWon ? WatchTokens.inkSoft : WatchTokens.ink)
            }
            HStack(spacing: 4) {
                Text(homeAbbr)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(homeWon ? WatchTokens.ink : WatchTokens.inkSoft)
                Spacer()
                Text(game.intHomeScore ?? "0")
                    .font(.system(size: 13, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(homeWon ? WatchTokens.ink : WatchTokens.inkSoft)
            }
            Text("FINAL")
                .font(.system(size: 9, design: .monospaced).weight(.semibold))
                .tracking(1)
                .foregroundStyle(WatchTokens.inkFaint)
        }
    }

    // MARK: - Upcoming Game

    private var upcomingContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(awayAbbr) vs \(homeAbbr)")
                .font(.system(size: 13, design: .rounded).weight(isFavorite ? .semibold : .regular))
            if let date = game.standardDate {
                Text(date, style: .time)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WatchTokens.inkSoft)
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
