//
//  TournamentScoreView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/7/26.
//

import SwiftUI
import SportsCalModel

/// Displays a golf/tennis tournament with a mini leaderboard instead of head-to-head
struct TournamentScoreView: View {
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

    /// Top 5 + any favorite players not already in top 5
    private var displayEntries: [LeaderboardEntry] {
        let all = game.resolvedLeaderboard
        var result = Array(all.prefix(5))
        let favoriteExtras = all.dropFirst(5).filter { favorites.containsPlayer($0.name) }
        for fav in favoriteExtras.prefix(3) {
            result.append(fav)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tournament header
            HStack {
                if viewModel.appStorage.debugMode, game.idEvent?.hasPrefix(DebugGameFactory.isFakeEventPrefix) == true {
                    Text("DEBUG")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(.orange, in: RoundedRectangle(cornerRadius: 4))
                }
                if let sport = sportType {
                    Image(systemName: sport.systemImage)
                        .foregroundColor(sport.color)
                }
                if game.isMajor {
                    Text("MAJOR")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.gradient)
                        .clipShape(Capsule())
                }
                Text(game.strHomeTeam)
                    .font(.headline)
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

            // Round / status info
            if let progress = game.strProgress {
                Text(progress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Mini leaderboard
            let entries = displayEntries
            if !entries.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        let isFavPlayer = favorites.containsPlayer(entry.name)
                        HStack(spacing: 6) {
                            Text("\(entry.position)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            HeadshotView(url: entry.headshot, size: 24)
                            if isFavPlayer {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                            }
                            Text(entry.name)
                                .font(.subheadline)
                                .fontWeight(index == 0 || isFavPlayer ? .semibold : .regular)
                                .lineLimit(1)
                            if entry.isCut == true {
                                Text("CUT")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.red.opacity(0.8))
                                    .clipShape(Capsule())
                            } else if let movement = entry.movement, movement != 0 {
                                HStack(spacing: 1) {
                                    Image(systemName: movement < 0 ? "arrow.up" : "arrow.down")
                                    Text("\(abs(movement))")
                                }
                                .font(.caption2)
                                .foregroundColor(movement < 0 ? .green : .red)
                            }
                            if let thru = entry.thruHole {
                                Text(thru)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(entry.score)
                                .font(.subheadline)
                                .fontWeight(index == 0 ? .semibold : .regular)
                                .foregroundColor(index == 0 ? .primary : .secondary)
                        }
                        .opacity(entry.isCut == true ? 0.5 : 1.0)
                    }
                }
            } else if game.strAwayTeam != "TBD" {
                // Fallback: show leader info when leaderboard isn't available
                HStack {
                    Text(game.strAwayTeam)
                        .font(.subheadline)
                    Spacer()
                    if let score = game.intAwayScore {
                        Text(score)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            } else if let date = game.standardDate {
                // Scheduled tournament with no details yet
                GameTimeLabel(date: date, includeDate: true)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Action menu
            HStack {
                Spacer()
                Menu {
                    CalendarButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                    NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}
