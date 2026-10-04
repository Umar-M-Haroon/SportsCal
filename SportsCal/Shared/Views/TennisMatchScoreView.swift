//
//  TennisMatchScoreView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/9/26.
//

import SwiftUI
import SportsCalModel

/// Compact list row for a tennis head-to-head match showing player names and set scores
struct TennisMatchScoreView: View {
    var game: Game
    @Environment(Favorites.self) private var favorites
    @Environment(GameViewModel.self) private var viewModel
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var isLive: Bool

    private var sportType: SportType? {
        guard let id = game.idLeague, let leagueID = Int(id), let league = Leagues(rawValue: leagueID) else { return nil }
        return SportType(league: league)
    }

    private var homeWinsSets: Int {
        guard let hLs = game.homeLinescores, let aLs = game.awayLinescores else { return 0 }
        return zip(hLs, aLs).filter { $0.0 > $0.1 }.count
    }

    private var awayWinsSets: Int {
        guard let hLs = game.homeLinescores, let aLs = game.awayLinescores else { return 0 }
        return zip(hLs, aLs).filter { $0.1 > $0.0 }.count
    }

    /// One VoiceOver sentence: "Live, Sinner vs Alcaraz, sets 1 to 0, 6-4, 3-2, 2nd Set".
    /// Home player first, matching the visual row order.
    private var accessibilityLabel: String {
        let matchup = "\(game.strHomeTeam) vs \(game.strAwayTeam)"
        var parts: [String] = []
        if isLive { parts.append("Live") }
        parts.append(matchup)
        let home = game.homeLinescores ?? [], away = game.awayLinescores ?? []
        if !home.isEmpty || !away.isEmpty {
            parts.append("sets \(homeWinsSets) to \(awayWinsSets)")
            let sets = (0..<max(home.count, away.count)).map { i in
                "\(i < home.count ? formatScore(home[i]) : "-")-\(i < away.count ? formatScore(away[i]) : "-")"
            }
            parts.append(sets.joined(separator: ", "))
        }
        if let status = game.displayStatus {
            parts.append(game.isFinalStatus ? status.lowercased() : status)
        } else if !isLive, let date = game.standardDate, date > Date() {
            parts.append(GameRowAccessibility.when(date))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Summary (header + players) reads as one VoiceOver element; the action
            // menu below stays its own element so it remains operable.
            VStack(alignment: .leading, spacing: 6) {
                // Header: sport icon + status + LIVE badge
                HStack {
                    if let sport = sportType {
                        Image(systemName: sport.systemImage)
                            .foregroundColor(sport.color)
                    }
                    if let progress = game.displayStatus {
                        Text(progress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if isLive {
                        Text("LIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }

                // Player rows with set scores
                let setCount = max(game.homeLinescores?.count ?? 0, game.awayLinescores?.count ?? 0)

                // Home player
                playerRow(
                    name: game.strHomeTeam,
                    setsWon: homeWinsSets,
                    isWinning: homeWinsSets > awayWinsSets,
                    linescores: game.homeLinescores,
                    opponentLinescores: game.awayLinescores,
                    setCount: setCount,
                    headshot: game.strHomeTeamBadge
                )

                // Away player
                playerRow(
                    name: game.strAwayTeam,
                    setsWon: awayWinsSets,
                    isWinning: awayWinsSets > homeWinsSets,
                    linescores: game.awayLinescores,
                    opponentLinescores: game.homeLinescores,
                    setCount: setCount,
                    headshot: game.strAwayTeamBadge
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(accessibilityLabel))

            // Action menu
            HStack {
                Spacer()
                Menu {
                    FavoriteMenu(game: game)
                        .environment(favorites)
                    CalendarButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                    NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel("Actions")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func playerRow(name: String, setsWon: Int, isWinning: Bool, linescores: [Double]?, opponentLinescores: [Double]?, setCount: Int, headshot: String? = nil) -> some View {
        HStack(spacing: 0) {
            HeadshotView(url: headshot, size: 24)
                .padding(.trailing, 6)
            Text(name)
                .font(.subheadline)
                .fontWeight(isWinning ? .semibold : .regular)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if setCount > 0 {
                ForEach(0..<setCount, id: \.self) { i in
                    let score = linescores.flatMap { i < $0.count ? $0[i] : nil }
                    let opScore = opponentLinescores.flatMap { i < $0.count ? $0[i] : nil }
                    let wonSet = score != nil && opScore != nil && score! > opScore!
                    Text(score.map { formatScore($0) } ?? "-")
                        .font(.subheadline.monospacedDigit())
                        .fontWeight(wonSet ? .bold : .regular)
                        .foregroundColor(wonSet ? .primary : .secondary)
                        .frame(width: 28, alignment: .center)
                }
            } else if let matchScore = (isWinning ? game.intHomeScore : game.intAwayScore) ?? (name == game.strHomeTeam ? game.intHomeScore : game.intAwayScore) {
                Text(matchScore)
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(.semibold)
                    .frame(width: 28, alignment: .center)
            }
        }
    }

    private func formatScore(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : "\(value)"
    }
}
