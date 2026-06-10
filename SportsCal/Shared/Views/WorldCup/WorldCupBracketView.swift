//
//  WorldCupBracketView.swift
//  SportsCal
//
//  Knockout bracket visualization. One column per round (Round of 32 → Final at the
//  2026 tournament). Round structure comes from the server (derived from ESPN), never
//  hardcoded, so the 48-team format renders correctly. Undecided slots show as TBD.
//

import SwiftUI
import SportsCalModel

struct WorldCupBracketView: View {
    let bracket: WorldCupBracket
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites

    private var accent: Color { .app(.soccer) }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: .appSpace4) {
                ForEach(Array(bracket.rounds.enumerated()), id: \.offset) { _, round in
                    VStack(alignment: .leading, spacing: .appSpace3) {
                        Text(round.roundName.uppercased())
                            .font(.appFootnote)
                            .foregroundStyle(accent)
                        ForEach(Array(round.matches.enumerated()), id: \.offset) { _, match in
                            cell(for: match)
                        }
                    }
                }

                if let third = bracket.thirdPlacePlayoff {
                    VStack(alignment: .leading, spacing: .appSpace3) {
                        Text("THIRD PLACE")
                            .font(.appFootnote)
                            .foregroundStyle(accent)
                        cell(for: third)
                    }
                }
            }
            .padding(.appSpace2)
        }
    }

    @ViewBuilder
    private func cell(for match: WorldCupBracketMatch) -> some View {
        if let eventID = match.eventID,
           let gwt = viewModel.worldCupGameWithTeams(eventID: eventID),
           let home = gwt.homeTeam, let away = gwt.awayTeam {
            NavigationLink {
                AdaptiveGameDetail(game: gwt.game, homeTeam: home, awayTeam: away)
                    .environment(viewModel)
                    .environment(favorites)
            } label: {
                WorldCupBracketMatchCell(match: match, accent: accent)
            }
            .buttonStyle(.plain)
        } else {
            WorldCupBracketMatchCell(match: match, accent: accent)
        }
    }
}

struct WorldCupBracketMatchCell: View {
    let match: WorldCupBracketMatch
    var accent: Color = .app(.soccer)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sideRow(
                name: match.homeTeamName ?? match.homePlaceholder ?? "TBD",
                badge: match.homeTeamBadge,
                score: match.homeScore,
                isWinner: match.winner == .home,
                isResolved: match.homeTeamName != nil
            )
            sideRow(
                name: match.awayTeamName ?? match.awayPlaceholder ?? "TBD",
                badge: match.awayTeamBadge,
                score: match.awayScore,
                isWinner: match.winner == .away,
                isResolved: match.awayTeamName != nil
            )
            if let agg = match.aggregateScore {
                Text(agg)
                    .font(.appFootnote)
                    .foregroundStyle(Color.appInkFaint)
            }
        }
        .frame(width: 184, alignment: .leading)
        .appCard(fill: Color.appAlt)
    }

    private func sideRow(name: String, badge: String?, score: String?, isWinner: Bool, isResolved: Bool) -> some View {
        HStack(spacing: .appSpace2) {
            WCBadge(url: badge, size: 20)
            Text(name)
                .font(.appCaption)
                .fontWeight(isWinner ? .bold : .regular)
                .foregroundStyle(isResolved ? (isWinner ? accent : Color.appInk) : Color.appInkFaint)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let score, !score.isEmpty {
                Text(score)
                    .font(.appCallout)
                    .fontWeight(isWinner ? .bold : .regular)
                    .foregroundStyle(isWinner ? accent : Color.appInk)
            }
        }
    }
}
