//
//  CompactGameRowView.swift
//  SportsCal (iOS)
//
//  A dense two-line scoreboard row for team-sport Browse lists. Far shorter than
//  GameScoreView (~44pt vs ~100pt) so a day's games scan at a glance. Taps through to
//  the full game detail. Away on top, home on top for soccer (`Game.displaysHomeFirst`).
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
    /// The status column grows with Dynamic Type so "Final (2OT)" or "Bot 9th" isn't cut off.
    @ScaledMetric(relativeTo: .caption2) private var statusWidth: CGFloat = 62

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
                    let sides = game.displayedSides
                    teamLine(side: sides.first)
                    teamLine(side: sides.second)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailing
                    .frame(width: statusWidth, alignment: .trailing)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(GameRowAccessibility.label(
                game: game,
                awayName: awayTeam.strTeam ?? game.strAwayTeam,
                homeName: homeTeam.strTeam ?? game.strHomeTeam,
                awayScore: awayScore,
                homeScore: homeScore,
                isLive: isLive
            )))
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
    private func teamLine(side: GameSituation.Side) -> some View {
        let isHome = side == .home
        let team = isHome ? homeTeam : awayTeam
        let score = isHome ? homeScore : awayScore
        let seed = isHome ? game.homeSeed : game.awaySeed
        // ESPN's winner first: a shootout winner is bold on a level score.
        let winning = game.winningSide == side
        let redCards = game.redCards(side)
        HStack(spacing: 6) {
            badge(team.strTeamBadge)
            SeededName.text(label(team), seed: seed, isRank: game.isCollegeFootball)
                .font(.subheadline)
                .fontWeight(winning ? .semibold : .regular)
                .foregroundStyle(hasScores && !winning ? .secondary : .primary)
                .lineLimit(1)
            if redCards > 0 {
                SoccerRedCardMark(count: redCards)
            }
            Spacer(minLength: 4)
            if let score {
                Text("\(score)")
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(winning ? .semibold : .regular)
                    .foregroundStyle(winning ? .primary : .secondary)
            }
        }
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 2) {
            status
            if isLive, let situation = game.situation {
                compactSituation(situation)
            } else if !isLive, !hasScores, let network = game.broadcasts?.first {
                Text(network)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if let number = game.doubleheaderGame {
                Text("Game \(number)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // "4–3 pens" / "Agg 3–2" under the status. Two-leg ties show the
            // aggregate; a shootout outranks it.
            if let decider = game.shootoutLine ?? game.aggregateLine {
                Text(decider)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if game.isPreseason {
                Text("Preseason")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// The live state in a few points: bases and outs, who has the ball and the down,
    /// or who's due up between half-innings.
    @ViewBuilder
    private func compactSituation(_ situation: GameSituation) -> some View {
        Group {
            if game.sportType == .mlb, situation.hasBaseballState {
                if let next = situation.dueUpSide {
                    Text("\(label(next == .home ? homeTeam : awayTeam)) up")
                } else {
                    HStack(spacing: 4) {
                        BaseDiamond(first: situation.onFirst == true, second: situation.onSecond == true,
                                    third: situation.onThird == true, size: 13, tint: .secondary)
                        if let outs = situation.outs {
                            OutsIndicator(outs: outs, dotSize: 4, tint: .secondary)
                        }
                    }
                }
            } else if game.sportType == .nfl, situation.hasFootballState {
                HStack(spacing: 2) {
                    if let side = situation.possession {
                        Image(systemName: "football.fill").imageScale(.small)
                            .foregroundStyle(situation.isRedZone == true ? Color.red : Color.secondary)
                        Text(label(side == .home ? homeTeam : awayTeam))
                    }
                    if let short = situation.shortDownDistanceText {
                        Text(short)
                    }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        // Spoken by the row's combined label.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var status: some View {
        if isLive {
            HStack(spacing: 3) {
                Circle().fill(.red).frame(width: 6, height: 6)
                Text(game.displayStatus ?? "LIVE")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        } else if hasScores, let status = game.displayStatus {
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } else if let date = game.standardDate {
            GameTimeLabel(date: date, isTBD: game.isTimeTBD)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
