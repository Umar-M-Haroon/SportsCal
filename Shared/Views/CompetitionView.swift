//
//  CompetitionView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/4/22.
//

import SwiftUI
import SportsCalModel

struct CompetitionView: View {
    var competition: String
    @State var isHidden: Bool = false
    @EnvironmentObject var appStorage: UserDefaultStorage
    var body: some View {
        HStack {
            Toggle(isOn: $isHidden) {
                Text(competition)
            }
            .onChange(of: isHidden) { newValue in
                if appStorage.hiddenCompetitions.contains(where: {$0 == competition}) {
                    appStorage.hiddenCompetitions.removeAll(where: {$0 == competition})
                } else {
                    appStorage.hiddenCompetitions.append(competition)
                }
                appStorage.objectWillChange.send()
            }
        }
    }
}

struct CompetitionView_Previews: PreviewProvider {
    static var previews: some View {
        CompetitionView(competition: "Serie A")
    }
}
