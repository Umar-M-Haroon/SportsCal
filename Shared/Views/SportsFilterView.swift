//
//  SportsFilterView.swift
//  SportsCal
//
//  Created by Umar Haroon on 10/23/22.
//

import Foundation
import SwiftUI
import SportsCalModel
struct SportsFilterView: View {
    var sport: SportType
    @ObservedObject var appStorage: UserDefaultStorage
    
    var body: some View {
        Button {
            withAnimation {
                switch sport {
                case .basketball:
                    if SubscriptionManager.shared.subscriptionStatus == .subscribed {
                        appStorage.shouldShowNBA.toggle()
                    } else {
                        appStorage.switchTo(sportType: .basketball)
                    }
                case .soccer:
                    if SubscriptionManager.shared.subscriptionStatus == .subscribed {
                        appStorage.shouldShowSoccer.toggle()
                    } else {
                        appStorage.switchTo(sportType: .soccer)
                    }
                case .hockey:
                    if SubscriptionManager.shared.subscriptionStatus == .subscribed {
                        appStorage.shouldShowNHL.toggle()
                    } else {
                        appStorage.switchTo(sportType: .hockey)
                    }
                case .mlb:
                    if SubscriptionManager.shared.subscriptionStatus == .subscribed {
                        appStorage.shouldShowMLB.toggle()
                    } else {
                        appStorage.switchTo(sportType: .mlb)
                    }
                case .nfl:
                    if SubscriptionManager.shared.subscriptionStatus == .subscribed {
                        appStorage.shouldShowNFL.toggle()
                    } else {
                        appStorage.switchTo(sportType: .nfl)
                    }
                }
            }
        } label: {
            HStack {
                Image(sport.rawValue)
                    .font(.footnote)
//                    .modifier(SportsTint(sport: sport))
                Text(sport.capitalized)
                    .font(.footnote)
                    .bold()
            }

        }
        .buttonBorderStyle(isDisabled())
        .buttonBorderShape(.capsule)
//        .padding(6)
    }
    
    func isDisabled() -> Bool {
        
        switch sport {
        case .basketball:
            return appStorage.shouldShowNBA
        case .soccer:
            return appStorage.shouldShowSoccer
        case .hockey:
            return appStorage.shouldShowNHL
        case .mlb:
            return appStorage.shouldShowMLB
        case .nfl:
            return appStorage.shouldShowNFL
        }
    }
}

extension Button {
    @ViewBuilder
    func buttonBorderStyle(_ isSelected: Bool) -> some View {
        if isSelected {
            self.buttonStyle(BorderedProminentButtonStyle())
        } else {
            self.buttonStyle(BorderedButtonStyle())
        }
    }
}

struct SportsFilterView_Previews: PreviewProvider {
    static var appStorage: UserDefaultStorage = UserDefaultStorage()
    static var previews: some View {
        ScrollView(.horizontal) {
            HStack {
//                SportsFilterView(sport: .soccer, appStorage: appStorage)
                SportsFilterView(sport: .soccer, appStorage: appStorage)
                SportsFilterView(sport: .basketball, appStorage: appStorage)
                
                SportsFilterView(sport: .nfl, appStorage: appStorage)
                
                SportsFilterView(sport: .hockey, appStorage: appStorage)
                
                SportsFilterView(sport: .mlb, appStorage: appStorage)
                SportsFilterView(sport: .soccer, appStorage: appStorage)
            }
        }
    }
}
