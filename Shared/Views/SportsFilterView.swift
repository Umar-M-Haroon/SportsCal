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
    @Binding var shouldShowPromoCount: Bool
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
                        shouldShowPromoCount = true
                    }
                case .soccer:
                    if SubscriptionManager.shared.subscriptionStatus == .subscribed {
                        appStorage.shouldShowSoccer.toggle()
                    } else {
                        appStorage.switchTo(sportType: .soccer)
                        shouldShowPromoCount = true
                    }
                case .hockey:
                    if SubscriptionManager.shared.subscriptionStatus == .subscribed {
                        appStorage.shouldShowNHL.toggle()
                    } else {
                        appStorage.switchTo(sportType: .hockey)
                        shouldShowPromoCount = true
                    }
                case .mlb:
                    if SubscriptionManager.shared.subscriptionStatus == .subscribed {
                        appStorage.shouldShowMLB.toggle()
                    } else {
                        appStorage.switchTo(sportType: .mlb)
                        shouldShowPromoCount = true
                    }
                case .nfl:
                    if SubscriptionManager.shared.subscriptionStatus == .subscribed {
                        appStorage.shouldShowNFL.toggle()
                    } else {
                        appStorage.switchTo(sportType: .nfl)
                        shouldShowPromoCount = true
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: sportToSystemImage())
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
    
    func sportToSystemImage() -> String {
        switch sport {
        case .soccer:
            return "soccerball.inverse"
        case .basketball:
            return "basketball"
        case .hockey:
            return "hockey.puck"
        case .mlb:
            return "baseball"
        case .nfl:
            return "football"
        }
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
                SportsFilterView(sport: .soccer, shouldShowPromoCount: .constant(false), appStorage: appStorage)
                SportsFilterView(sport: .basketball, shouldShowPromoCount: .constant(false), appStorage: appStorage)
                SportsFilterView(sport: .nfl, shouldShowPromoCount: .constant(false), appStorage: appStorage)
                SportsFilterView(sport: .hockey, shouldShowPromoCount: .constant(false), appStorage: appStorage)
                SportsFilterView(sport: .mlb, shouldShowPromoCount: .constant(false), appStorage: appStorage)
                SportsFilterView(sport: .soccer, shouldShowPromoCount: .constant(false), appStorage: appStorage)
            }
        }
    }
}
