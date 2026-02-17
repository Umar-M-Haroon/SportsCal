//
//  WatchGameDetailView.swift
//  SportsCalWatch
//
//  Full detail view for team sports on Watch.
//  Shows scores, linescore table, last play, and stat leaders.
//  Sets NSUserActivity for Handoff to iPhone.
//

import SwiftUI
import SportsCalModel

struct WatchGameDetailView: View {
    let game: Game
    let teams: [Team]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Score Header
                scoreHeader

                // Linescore
                if let homeLine = game.homeLinescores, let awayLine = game.awayLinescores,
                   !homeLine.isEmpty {
                    linescoreView(homeLine: homeLine, awayLine: awayLine)
                }

                // Last Play
                if let lastPlay = game.lastPlay, !lastPlay.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Play")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(lastPlay)
                            .font(.system(size: 11))
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Stat Leaders
                if let homeLeaders = game.homeLeaders, let awayLeaders = game.awayLeaders {
                    leadersView(homeLeaders: homeLeaders, awayLeaders: awayLeaders)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(statusTitle)
        .userActivity("com.komodo.SportsCal.gameDetail") { activity in
            activity.title = "\(game.strAwayTeam) vs \(game.strHomeTeam)"
            activity.isEligibleForHandoff = true
            if let eventID = game.idEvent {
                activity.userInfo = ["eventID": eventID]
                activity.webpageURL = URL(string: "sportscal://game/\(eventID)")
            }
        }
    }

    // MARK: - Score Header

    private var scoreHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(spacing: 2) {
                    Text(awayAbbr)
                        .font(.system(size: 14, weight: .semibold))
                    if isLive || game.isCompleted == true {
                        Text(game.intAwayScore ?? "0")
                            .font(.system(size: 28, weight: .bold))
                    }
                }
                Spacer()
                VStack(spacing: 2) {
                    if let progress = game.strProgress ?? game.strStatus {
                        Text(progress)
                            .font(.system(size: 11))
                            .foregroundStyle(isLive ? .green : .secondary)
                    }
                    if let date = game.standardDate, !isLive && game.isCompleted != true {
                        Text(date, style: .time)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(homeAbbr)
                        .font(.system(size: 14, weight: .semibold))
                    if isLive || game.isCompleted == true {
                        Text(game.intHomeScore ?? "0")
                            .font(.system(size: 28, weight: .bold))
                    }
                }
            }
        }
    }

    // MARK: - Linescore

    private func linescoreView(homeLine: [Double], awayLine: [Double]) -> some View {
        VStack(spacing: 2) {
            let periodCount = max(homeLine.count, awayLine.count)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 1) {
                    // Header
                    HStack(spacing: 0) {
                        Text("")
                            .frame(width: 30)
                        ForEach(0..<periodCount, id: \.self) { i in
                            Text(periodLabel(i, total: periodCount))
                                .font(.system(size: 8, weight: .semibold))
                                .frame(width: 20)
                        }
                        Text("T")
                            .font(.system(size: 8, weight: .semibold))
                            .frame(width: 24)
                    }
                    // Away row
                    HStack(spacing: 0) {
                        Text(awayAbbr)
                            .font(.system(size: 9, weight: .medium))
                            .frame(width: 30, alignment: .leading)
                        ForEach(0..<periodCount, id: \.self) { i in
                            Text(i < awayLine.count ? "\(Int(awayLine[i]))" : "-")
                                .font(.system(size: 9, design: .monospaced))
                                .frame(width: 20)
                        }
                        Text(game.intAwayScore ?? "0")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .frame(width: 24)
                    }
                    // Home row
                    HStack(spacing: 0) {
                        Text(homeAbbr)
                            .font(.system(size: 9, weight: .medium))
                            .frame(width: 30, alignment: .leading)
                        ForEach(0..<periodCount, id: \.self) { i in
                            Text(i < homeLine.count ? "\(Int(homeLine[i]))" : "-")
                                .font(.system(size: 9, design: .monospaced))
                                .frame(width: 20)
                        }
                        Text(game.intHomeScore ?? "0")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .frame(width: 24)
                    }
                }
            }
        }
    }

    private func periodLabel(_ index: Int, total: Int) -> String {
        let sport = game.sportType
        if sport == .hockey { return "P\(index + 1)" }
        if sport == .mlb { return "\(index + 1)" }
        if sport == .nfl { return "Q\(index + 1)" }
        if sport == .basketball { return "Q\(index + 1)" }
        return "\(index + 1)"
    }

    // MARK: - Leaders

    private func leadersView(homeLeaders: [GameLeader], awayLeaders: [GameLeader]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Leaders")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(homeLeaders.prefix(3).enumerated()), id: \.offset) { idx, leader in
                HStack {
                    Text(leader.categoryDisplay)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                    VStack(alignment: .leading) {
                        Text(leader.playerName)
                            .font(.system(size: 10, weight: .medium))
                        Text(leader.displayValue)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if idx < awayLeaders.count {
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(awayLeaders[idx].playerName)
                                .font(.system(size: 10, weight: .medium))
                            Text(awayLeaders[idx].displayValue)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var isLive: Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty && status != "ft" && status != "aet" &&
               status != "not started" && status != "ns" &&
               game.intHomeScore != nil && game.intAwayScore != nil
    }

    private var statusTitle: String {
        if isLive { return "Live" }
        if game.isCompleted == true { return "Final" }
        return "Upcoming"
    }

    private var homeAbbr: String {
        abbreviation(teamID: game.idHomeTeam, name: game.strHomeTeam)
    }

    private var awayAbbr: String {
        abbreviation(teamID: game.idAwayTeam, name: game.strAwayTeam)
    }

    private func abbreviation(teamID: String?, name: String) -> String {
        if let id = teamID,
           let team = Team.getTeamInfoFrom(teams: teams, teamID: id),
           let short = team.strTeamShort {
            return short
        }
        return String(name.prefix(3)).uppercased()
    }
}
