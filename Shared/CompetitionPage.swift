//
//  CompetitionPage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/4/22.
//

import SwiftUI

struct CompetitionPage: View {
    var competitions: [String] = [
        "Coppa Italia",
        "Eredivisie",
        "Bundesliga",
        "Ligue 1",
        "Serie A",
        "EFL Cup",
        "Championship",
        "Premier League",
        "La Liga",
        "UEFA Champions League"
    ]
    @EnvironmentObject var appStorage: UserDefaultStorage
    var competitionStorage: [Binding<Bool>] = []
    var body: some View {
        List(competitions.indices, id: \.self) { index in
            CompetitionView(competition: competitions[index], isHidden: competitionStorage[index])
        }
        .navigationTitle("Hide Competitions")
    }
}

struct CompetitionPage_Previews: PreviewProvider {
    static var previews: some View {
        CompetitionPage()
    }
}
