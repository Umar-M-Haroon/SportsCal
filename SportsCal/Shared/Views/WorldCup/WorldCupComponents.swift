//
//  WorldCupComponents.swift
//  SportsCal
//
//  Small shared building blocks for the World Cup hub: a team-badge image and a
//  compact match row that navigates to the standard game detail.
//

import SwiftUI
import SportsCalModel
import NukeUI

/// Square team/flag badge with a soccerball fallback.
///
/// Uses Nuke's `LazyImage` (same pipeline as `IndividualTeamView`) rather than
/// `AsyncImage`: the flag PNGs are downsampled off the main thread to the badge
/// size and held in Nuke's memory/disk cache, so re-renders return the decoded
/// image synchronously — no main-thread decode hitch and no placeholder→image
/// flash when the hero re-renders or remounts.
struct WCBadge: View {
    let url: String?
    var size: CGFloat = 28

    var body: some View {
        if let imageURL = Self.resolvedURL(url) {
            LazyImage(
                request: ImageRequest(
                    url: imageURL,
                    processors: [.resize(size: CGSize(width: size, height: size),
                                         unit: .points, contentMode: .aspectFit)]
                )
            ) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)
        } else {
            placeholder.frame(width: size, height: size)
        }
    }

    /// TheSportsDB badges need a `/preview` suffix for the small variant; ESPN
    /// flag/logo URLs are used as-is.
    private static func resolvedURL(_ urlString: String?) -> URL? {
        guard let urlString, !urlString.isEmpty else { return nil }
        if urlString.contains("thesportsdb.com") {
            return URL(string: urlString + "/preview")
        }
        return URL(string: urlString)
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
