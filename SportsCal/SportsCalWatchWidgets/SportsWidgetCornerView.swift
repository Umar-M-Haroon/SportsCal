//
//  SportsWidgetCornerView.swift
//  SportsCalWatchWidgets
//
//  watchOS-only accessoryCorner complication.
//  Live game: Gauge arc showing relative score balance.
//  Upcoming: Countdown text to next game.
//  Tournament: Gauge showing leader score relative to par/field.
//

import SwiftUI
import WidgetKit
import SportsCalModel

struct SportsWidgetCornerView: View {
    var entry: Provider.Entry

    var body: some View {
        if let game = entry.game?.first {
            if isLive(game) {
                liveCorner(game)
            } else {
                upcomingCorner(game)
            }
        } else {
            // No games — show app icon
            Text("SC")
                .font(.system(size: 12, weight: .bold))
                .widgetLabel("SportsCal")
        }
    }

    // MARK: - Live Game Corner

    private func liveCorner(_ game: Game) -> some View {
        let sportType = game.sportType ?? .basketball
        let homeScore = Double(game.intHomeScore ?? "0") ?? 0
        let awayScore = Double(game.intAwayScore ?? "0") ?? 0
        let total = max(homeScore + awayScore, 1)

        return Gauge(value: awayScore, in: 0...total) {
            Image(systemName: sportType.widgetSystemImage)
                .foregroundStyle(sportType.widgetColor)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetLabel {
            let homeAbbr = abbreviation(teamID: game.idHomeTeam, name: game.strHomeTeam)
            let awayAbbr = abbreviation(teamID: game.idAwayTeam, name: game.strAwayTeam)
            Text("\(awayAbbr) \(game.intAwayScore ?? "0") - \(homeAbbr) \(game.intHomeScore ?? "0")")
        }
    }

    // MARK: - Upcoming Corner

    private func upcomingCorner(_ game: Game) -> some View {
        let sportType = game.sportType ?? .basketball

        return Group {
            if let date = game.standardDate {
                Text(date, style: .timer)
                    .font(.system(size: 12))
            } else {
                Image(systemName: sportType.widgetSystemImage)
            }
        }
        .widgetLabel {
            if game.isIndividualSport {
                Text(game.strHomeTeam)
            } else {
                let homeAbbr = abbreviation(teamID: game.idHomeTeam, name: game.strHomeTeam)
                let awayAbbr = abbreviation(teamID: game.idAwayTeam, name: game.strAwayTeam)
                Text("\(awayAbbr) @ \(homeAbbr)")
            }
        }
    }

    // MARK: - Helpers

    private func isLive(_ game: Game) -> Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty &&
               status != "ft" && status != "aet" &&
               status != "not started" && status != "ns" &&
               game.intHomeScore != nil && game.intAwayScore != nil
    }

    private func abbreviation(teamID: String?, name: String) -> String {
        if let id = teamID,
           let team = Team.getTeamInfoFrom(teams: entry.teams, teamID: id),
           let short = team.strTeamShort {
            return short
        }
        return String(name.prefix(3)).uppercased()
    }
}
