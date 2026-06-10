//
//  WorldCupComponents.swift
//  SportsCal
//
//  Small shared building blocks for the World Cup hub: a team-badge image and a
//  compact match row that navigates to the standard game detail.
//

import SwiftUI
import SportsCalModel

/// Square team/flag badge with a soccerball fallback.
struct WCBadge: View {
    let url: String?
    var size: CGFloat = 28

    var body: some View {
        if let urlString = url, let imageURL = URL(string: urlString) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    placeholder
                }
            }
            .frame(width: size, height: size)
        } else {
            placeholder.frame(width: size, height: size)
        }
    }

    private var placeholder: some View {
        Image(systemName: "soccerball")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.appInkFaint)
    }
}

/// A compact World Cup match row. Tapping navigates to the full game detail when
/// teams resolve; otherwise it renders as a static row.
struct WorldCupMatchRow: View {
    let gameWithTeams: GameWithTeams
    @Binding var sheetType: SheetType?
    @Binding var shouldShowSportsCalProAlert: Bool
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @Environment(UserDefaultStorage.self) private var storage

    var body: some View {
        let game = gameWithTeams.game
        if let home = gameWithTeams.homeTeam, let away = gameWithTeams.awayTeam {
            let isPreGame = game.strStatus == "pre" || game.strStatus == "NS"
            if let homeScore = Int(game.intHomeScore ?? ""),
               let awayScore = Int(game.intAwayScore ?? ""),
               !isPreGame {
                GameScoreView(
                    homeTeam: home,
                    awayTeam: away,
                    homeScore: homeScore,
                    awayScore: awayScore,
                    game: game,
                    shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                    sheetType: $sheetType,
                    isLive: game.strStatus == "in"
                )
                .environment(favorites)
                .environment(viewModel)
            } else {
                UpcomingGameView(
                    homeTeam: home,
                    awayTeam: away,
                    game: game,
                    showCountdown: .constant(storage.showStartTime),
                    shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                    sheetType: $sheetType,
                    dateFormat: storage.dateFormat,
                    isFavorite: favorites.contains(game)
                )
                .environment(favorites)
                .environment(viewModel)
            }
        }
    }
}
