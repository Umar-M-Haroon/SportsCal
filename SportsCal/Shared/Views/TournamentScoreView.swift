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

            // Mini leaderboard (top 5 in compact view)
            let entries = Array(game.resolvedLeaderboard.prefix(5))
            if !entries.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        HStack(spacing: 6) {
                            Text("\(entry.position)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            HeadshotView(url: entry.headshot, size: 24)
                            Text(entry.name)
                                .font(.subheadline)
                                .fontWeight(index == 0 ? .semibold : .regular)
                                .lineLimit(1)
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
                Text(date.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
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
