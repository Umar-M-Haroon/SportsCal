//
//  CompetitionPage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/4/22.
//

import SwiftUI
import SportsCalModel

struct CompetitionPage: View {
    var competitions: [Leagues]
    @Environment(UserDefaultStorage.self) private var appStorage
    var body: some View {
        List(competitions, id: \.self) { league in
            CompetitionView(league: league, isShown: !appStorage.hiddenCompetitions.contains(league.leagueName))
                .environment(appStorage)
        }
        .navigationTitle("Show Competitions")
    }
}

#Preview {
    @Previewable @State var storage = UserDefaultStorage()
    CompetitionPage(competitions: [.English_Premier_League, .La_Liga, .Serie_A])
        .environment(storage)
}
