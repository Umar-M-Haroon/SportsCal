//
//  GameView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/15/23.
//

import SwiftUI
import SportsCalModel
struct GameView: View {
    @EnvironmentObject var viewModel: GameViewModel
    @EnvironmentObject var favorites: Favorites
    @EnvironmentObject var storage: UserDefaultStorage
    @State var game: Game
    @State private var sheetType: SheetType? = nil
    @State var shouldShowSportsCalProAlert: Bool = false
    var body: some View {
        if let (homeTeam, awayTeam) = viewModel.getTeams(for: game) {
            if let homeScore = Int(game.intHomeScore ?? ""), let awayScore = Int(game.intAwayScore ?? "") {
                GameScoreView(homeTeam: homeTeam, awayTeam: awayTeam, homeScore: homeScore, awayScore: awayScore, game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: false)
                    .environmentObject(favorites)
            } else {
                UpcomingGameView(homeTeam: homeTeam, awayTeam: awayTeam, game: game, showCountdown: storage.$showStartTime, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, dateFormat:  storage.dateFormat)
                    .environmentObject(favorites)
            }
        }
    }
}

//struct GameView_Previews: PreviewProvider {
//    static var previews: some View {
//        GameView()
//    }
//}
