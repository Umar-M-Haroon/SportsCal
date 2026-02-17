//
//  CompetitionView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/4/22.
//

import SwiftUI
import WidgetKit
import SportsCalModel

struct CompetitionView: View {
    var competition: String
    @State var isShown: Bool = true
    @Environment(UserDefaultStorage.self) private var appStorage

    var body: some View {
        HStack {
            Toggle(isOn: $isShown) {
                Text(competition)
            }
            .onChange(of: isShown) { oldValue, newValue in
                if newValue {
                    appStorage.hiddenCompetitions.removeAll(where: { $0 == competition })
                } else {
                    if !appStorage.hiddenCompetitions.contains(competition) {
                        appStorage.hiddenCompetitions.append(competition)
                    }
                }
                appStorage.syncHiddenCompetitions()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        .onAppear {
            isShown = !appStorage.hiddenCompetitions.contains(competition)
        }
    }
}

#Preview {
    CompetitionView(competition: "Serie A")
        .environment(UserDefaultStorage())
}
