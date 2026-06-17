//
//  CompactGameRowView.swift
//  SportsCal (iOS)
//
//  A dense two-line scoreboard row for team-sport Browse lists. Far shorter than
//  GameScoreView (~44pt vs ~100pt) so a day's games scan at a glance. Taps through to
//  the full game detail.
//

import SwiftUI
import SportsCalModel
import NukeUI

struct CompactGameRowView: View {
    var homeTeam: Team
    var awayTeam: Team
    var game: Game
    @Environment(Favorites.self) private var favorites
    @Environment(GameViewModel.self) private var viewModel
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var isLive: Bool

    private var awayScore: Int? { game.intAwayScore.flatMap { Int($0) } }
    private var homeScore: Int? { game.intHomeScore.flatMap { Int($0) } }
    private var hasScores: Bool { awayScore != nil && homeScore != nil }

    var body: some View {
        NavigationLink {
            AdaptiveGameDetail(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                .environment(viewModel)
                .environment(favorites)
        } label: {
            HStack(spacing: 10) {
                VStack(spacing: 3) {
                    teamLine(team: awayTeam, score: awayScore,
                             winning: (awayScore ?? 0) > (homeScore ?? 0), seed: game.awaySeed)
                    teamLine(team: homeTeam, score: homeScore,
                             winning: (homeScore ?? 0) > (awayScore ?? 0), seed: game.homeSeed)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailing
                    .frame(width: 62, alignment: .trailing)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
#if canImport(ActivityKit) && os(iOS)
            if isLive {
                LiveActivityFollowMenu(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                    .environment(viewModel)
            }
            if !isLive {
                AutoFollowButton(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                    .environment(viewModel)
            }
#endif
            FavoriteMenu(game: game)
                .environment(favorites)
            CalendarButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
            NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
        }
    }

    @ViewBuilder
    private func teamLine(team: Team, score: Int?, winning: Bool, seed: Int?) -> some View {
        HStack(spacing: 6) {
            badge(team.strTeamBadge)
            Text(seed != nil ? "(\(seed!)) \(label(team))" : label(team))
                .font(.subheadline)
                .fontWeight(winning ? .semibold : .regular)
                .foregroundStyle(hasScores && !winning ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let score {
                Text("\(score)")
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(winning ? .semibold : .regular)
                    .foregroundStyle(winning ? .primary : .secondary)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isLive {
            HStack(spacing: 3) {
                Circle().fill(.red).frame(width: 6, height: 6)
                Text(game.displayStatus ?? "LIVE")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        } else if hasScores, let status = game.displayStatus {
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if let date = game.standardDate {
            GameTimeLabel(date: date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func label(_ team: Team) -> String {
        team.strTeamShort ?? Team.shortCode(strTeamShort: nil, name: team.strTeam ?? "TBD")
    }

    @ViewBuilder
    private func badge(_ urlString: String?) -> some View {
        if let urlString, let url = badgeURL(urlString) {
            LazyImage(request: ImageRequest(url: url, processors: [.resize(size: CGSize(width: 22, height: 22))])) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Circle().fill(Color.gray.opacity(0.15))
                }
            }
            .frame(width: 22, height: 22)
        } else {
            Circle().fill(Color.gray.opacity(0.15)).frame(width: 22, height: 22)
        }
    }

    private func badgeURL(_ urlString: String) -> URL? {
        if urlString.contains("thesportsdb.com") {
            return URL(string: urlString + "/preview")
        }
        return URL(string: urlString)
    }
}
