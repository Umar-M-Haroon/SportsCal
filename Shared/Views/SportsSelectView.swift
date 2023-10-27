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
    @Binding var shouldShow: Bool
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 5) {
                ForEach(SportType.allCases.indices, id: \.self) { index in
                    SportsFilterView(sport: SportType.allCases[index], isLive: currentlyLiveSports.contains(SportType.allCases[index]), shouldShowPromoCount: $shouldShowPromo, appStorage: storage)
                        .environmentObject(model)
//                        .frame(minHeight: 40)
                        .transition(.opacity)
                        .animation(.ripple(index: index), value: shouldShow)
                        .opacity(shouldShow ? 1 : 0)
                        .transition(.opacity)
                }
                .transition(.opacity)
                .opacity(shouldShow ? 1 : 0)
                        .transition(.opacity)
            }
                        .opacity(shouldShow ? 1 : 0)
        }
                .transition(.slide)
                        .opacity(shouldShow ? 1 : 0)
        .padding(.leading, 20)
    }
}

struct SportsSelectView_Previews: PreviewProvider {
    static var previews: some View {
        SportsSelectView(shouldShowPromo: false, shouldShow: .constant(true))
            .environmentObject(GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites()))
            .environmentObject(UserDefaultStorage())
    }
}
