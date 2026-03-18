//
//  MenuBarLabel.swift
//  SportsCal
//

#if os(macOS)
import SwiftUI
import SportsCalModel

struct MenuBarLabel: View {
    let liveFavorites: [GameWithTeams]
    let liveGames: [GameWithTeams]
    let upcomingFavorite: GameWithTeams?
    let liveCount: Int
    let todayCount: Int
    let liveSports: [SportType]

    @State private var tick = 0

    var body: some View {
        content
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                if rotatingGames.count > 1 {
                    tick += 1
                }
            }
    }

    private var rotatingGames: [GameWithTeams] {
        liveFavorites.isEmpty ? liveGames : liveFavorites
    }

    @ViewBuilder
    private var content: some View {
        if !rotatingGames.isEmpty {
            liveScoreLabel
        } else if let upcoming = upcomingFavorite, let gameDate = upcoming.game.standardDate {
            upcomingLabel(game: upcoming, gameDate: gameDate)
        } else if todayCount > 0 {
            todayCountLabel
        } else {
            Label("SportsCal", systemImage: "sportscourt.fill")
        }
    }

    private var liveScoreLabel: some View {
        let games = rotatingGames
        let idx = games.count > 1 ? tick % games.count : 0
        let gwt = games[idx]
        let game = gwt.game

        return HStack(spacing: 3) {
            if game.isIndividualSport {
                let name = gwt.homeTeam?.strTeamShort ?? String(game.strHomeTeam.prefix(3)).uppercased()
                if let leader = game.resolvedLeaderboard.first {
                    Text("\(name) \(leader.score)")
                        .font(.caption2)
                        .monospacedDigit()
                } else {
                    Text(name)
                        .font(.caption2)
                }
            } else {
                let away = gwt.awayTeam?.strTeamShort ?? String(game.strAwayTeam.prefix(3)).uppercased()
                let home = gwt.homeTeam?.strTeamShort ?? String(game.strHomeTeam.prefix(3)).uppercased()
                if let awayScore = game.intAwayScore, let homeScore = game.intHomeScore {
                    Text("\(away) \(awayScore) - \(home) \(homeScore)")
                        .font(.caption2)
                        .monospacedDigit()
                } else {
                    Text("\(away) @ \(home)")
                        .font(.caption2)
                }
            }

            if let progress = game.strProgress {
                Text(progress)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func upcomingLabel(game: GameWithTeams, gameDate: Date) -> some View {
        let remaining = gameDate.timeIntervalSince(Date())
        let name = game.homeTeam?.strTeamShort ?? String(game.game.strHomeTeam.prefix(3)).uppercased()

        return HStack(spacing: 3) {
            Text("⭑")
                .font(.caption2)

            if remaining > 6 * 3600 {
                Text("\(name) \(Self.shortTimeFormatter.string(from: gameDate))")
                    .font(.caption2)
                    .monospacedDigit()
            } else {
                let hours = Int(remaining) / 3600
                let minutes = (Int(remaining) % 3600) / 60
                if hours > 0 {
                    Text("\(name) in \(hours)h \(minutes)m")
                        .font(.caption2)
                        .monospacedDigit()
                } else {
                    Text("\(name) in \(minutes)m")
                        .font(.caption2)
                        .monospacedDigit()
                }
            }
        }
    }

    private var liveCountLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.red)
            ForEach(liveSports.prefix(3), id: \.self) { sport in
                Image(systemName: sport.systemImage)
                    .font(.system(size: 10))
            }
            Text("\(liveCount)")
                .font(.caption2)
                .monospacedDigit()
        }
    }

    private var todayCountLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "sportscourt.fill")
                .font(.system(size: 10))
            Text("\(todayCount)")
                .font(.caption2)
                .monospacedDigit()
        }
    }

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "a"
        f.pmSymbol = "p"
        return f
    }()
}
#endif
