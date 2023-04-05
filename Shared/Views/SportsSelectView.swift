//
//  SportsSelectVIew.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 1/21/23.
//

import SwiftUI
import SportsCalModel

struct SportsSelectView: View {
    @State var shouldShowPromo: Bool = false
    @EnvironmentObject var storage: UserDefaultStorage
    @State var currentlyLiveSports: [SportType] = []
    @EnvironmentObject var model: GameViewModel
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack {
                ForEach(SportType.allCases, id: \.self) { sport in
                    SportsFilterView(sport: sport, isLive: currentlyLiveSports.contains(sport), shouldShowPromoCount: $shouldShowPromo, appStorage: storage)
                        .environmentObject(model)
                }
            }
        }
        .padding(.leading, 20)
    }
}

struct SportsSelectView_Previews: PreviewProvider {
    static var previews: some View {
        SportsSelectView(shouldShowPromo: false)
            .environmentObject(UserDefaultStorage())
    }
}
