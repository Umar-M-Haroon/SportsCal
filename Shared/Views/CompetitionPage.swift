//
//  CompetitionPage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/4/22.
//

import SwiftUI
import SportsCalModel

struct CompetitionPage: View {
    var competitions: [String]
    @EnvironmentObject var appStorage: UserDefaultStorage
    var body: some View {
        List(competitions.indices, id: \.self) { index in
            CompetitionView(competition: competitions[index], isHidden: !appStorage.hiddenCompetitions.contains(where: {$0 == competitions[index]}))
                .environmentObject(appStorage)
        }
        .navigationTitle("Show Competitions")
    }
}

struct CompetitionPage_Previews: PreviewProvider {
    static var previews: some View {
        CompetitionPage(competitions: [])
    }
}
