//
//  LiveEventsView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 3/24/23.
//

import SwiftUI
import SportsCalModel

struct LiveEventsView: View {
    @EnvironmentObject var favorites: Favorites
    @EnvironmentObject var viewModel: GameViewModel
    @EnvironmentObject var storage: UserDefaultStorage
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var body: some View {
        if !viewModel.liveEvents.isEmpty {
            Section {
                ForEach(viewModel.liveEvents) { event in
                    if let homeScore = Int(event.intHomeScore ?? ""),
                       let awayScore = Int(event.intAwayScore ?? ""),
                       let (homeTeam, awayTeam) = viewModel.getTeams(for: event) {
                        GameScoreView(homeTeam: homeTeam, awayTeam: awayTeam, homeScore: homeScore, awayScore: awayScore, game: event, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: true)
                            .environmentObject(viewModel)
                    }
                }
            } header: {
                LiveAnimatedView()
            }
        } else {
            EmptyView()
        }
    }
}

