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
    var isLive: Bool = false
    @State var scale = 0.0
    @Binding var shouldShowPromoCount: Bool
    @ObservedObject var appStorage: UserDefaultStorage
    @EnvironmentObject var model: GameViewModel
    
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
                    model.getInfo()
                    model.filterSports()
                case .soccer:
                    if SubscriptionManager.shared.subscriptionStatus == .subscribed {
                        appStorage.shouldShowSoccer.toggle()
                    } else {
                        appStorage.switchTo(sportType: .soccer)
                        shouldShowPromoCount = true
                    }
                    model.getInfo()
                    model.filterSports()
                case .hockey:
                    if SubscriptionManager.shared.subscriptionStatus == .subscribed {
                        appStorage.shouldShowNHL.toggle()
                    } else {
                        appStorage.switchTo(sportType: .hockey)
                        shouldShowPromoCount = true
                    }
                    model.getInfo()
                    model.filterSports()
                case .mlb:
                    if SubscriptionManager.shared.subscriptionStatus == .subscribed {
                        appStorage.shouldShowMLB.toggle()
                    } else {
                        appStorage.switchTo(sportType: .mlb)
                        shouldShowPromoCount = true
                    }
                    model.getInfo()
                    model.filterSports()
                case .nfl:
                    if SubscriptionManager.shared.subscriptionStatus == .subscribed {
                        appStorage.shouldShowNFL.toggle()
                    } else {
                        appStorage.switchTo(sportType: .nfl)
                        shouldShowPromoCount = true
                    }
                    model.getInfo()
                    model.filterSports()
                }
            }
        } label: {
//            HStack(spacing: 4) {
                Image(systemName: sportToSystemImage())
                    .resizable()
                    .modifier(SportsTint(sport: sport))
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 15)
//                if isLive {
//                    LiveViewCircle()
//                }
//            }
        .buttonBorderShape(.capsule)
        .transition(.slide)
        }
        .buttonBorderStyle(isDisabled())
        .buttonBorderShape(.capsule)
        .opacity(scale)
        .scaleEffect(scale)
        .onAppear {
            let baseAnimation = Animation.spring()
                            let repeated = baseAnimation.repeatForever(autoreverses: true)
            
            withAnimation(baseAnimation) {
                scale = 1
            }
        }
    }
    
    func sportToSystemImage() -> String {
        switch sport {
        case .soccer:
            return "soccerball"
        case .basketball:
            return "basketball.fill"
        case .hockey:
            return "hockey.puck.fill"
        case .mlb:
            return "baseball.fill"
        case .nfl:
            return "football.fill"
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

struct SportsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.3 : 1)
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
