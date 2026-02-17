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
    @Environment(UserDefaultStorage.self) private var appStorage
    var body: some View {
        List(competitions.indices, id: \.self) { index in
            CompetitionView(competition: competitions[index], isShown: !appStorage.hiddenCompetitions.contains(where: {$0 == competitions[index]}))
                .environment(appStorage)
        }
        .navigationTitle("Show Competitions")
    }
}

#Preview {
    @Previewable @State var storage = UserDefaultStorage()
    CompetitionPage(competitions: ["Premier League", "La Liga", "Serie A"])
        .environment(storage)
}
