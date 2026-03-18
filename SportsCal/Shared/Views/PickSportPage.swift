//
//  PickSportPage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/19/22.
//

import SwiftUI
import SportsCalModel
struct PickSportPage: View {
    @State var subscriptionPresented: Bool = false
    @Environment(UserDefaultStorage.self) private var appStorage
    @Binding var sheetType: SheetType?
    @Environment(GameViewModel.self) private var viewModel
    var body: some View {
        @Bindable var bindableAppStorage = appStorage
        
        List {
            Section {
                Toggle(isOn: $bindableAppStorage.shouldShowNHL) {
                    Label {
                        Text("NHL")
                    } icon: {
                        Image(systemName: "hockey.puck.fill")
                            .modifier(SportsTint(sport: .hockey))
                    }
                }
                .onTapGesture {
//                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                        //                            appStorage.switchTo(sportType: .hockey)
//                        appStorage.shouldShowNFL = false
//                        appStorage.shouldShowNBA = false
//                        appStorage.shouldShowNHL.toggle()
//                        appStorage.shouldShowSoccer = false
//                        appStorage.shouldShowMLB = false
//                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowNFL) {
                    Label {
                        Text("NFL")
                    } icon: {
                        Image(systemName: "football.fill")
                            .modifier(SportsTint(sport: .nfl))
                    }
                }
                .onTapGesture {
//                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
//                        appStorage.shouldShowNFL.toggle()
//                        appStorage.shouldShowNBA = false
//                        appStorage.shouldShowNHL = false
//                        appStorage.shouldShowSoccer = false
//                        appStorage.shouldShowMLB = false
//                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowNBA) {
                    Label {
                        Text("NBA")
                    } icon: {
                        Image(systemName: "basketball.fill")
                            .modifier(SportsTint(sport: .basketball))
                    }
                }
                .onTapGesture {
//                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
//                        appStorage.shouldShowNFL = false
//                        appStorage.shouldShowNBA.toggle()
//                        appStorage.shouldShowNHL = false
//                        appStorage.shouldShowSoccer = false
//                        appStorage.shouldShowMLB = false
//                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowMLB) {
                    Label {
                      Text("MLB")
                    } icon: {
                        Image(systemName: "baseball.fill")
                            .modifier(SportsTint(sport: .mlb))
                    }
                }
                .onTapGesture {
//                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
//                        appStorage.shouldShowNFL = false
//                        appStorage.shouldShowNBA = false
//                        appStorage.shouldShowNHL = false
//                        appStorage.shouldShowSoccer = false
//                        appStorage.shouldShowMLB.toggle()
//                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowSoccer) {
                    Label {
                        Text("Soccer")
                    } icon: {
                        Image(systemName: "soccerball")
                            .modifier(SportsTint(sport: .soccer))
                    }
                }
                .onTapGesture {
//                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
//                        appStorage.shouldShowNFL = false
//                        appStorage.shouldShowNBA = false
//                        appStorage.shouldShowNHL = false
//                        appStorage.shouldShowSoccer.toggle()
//                        appStorage.shouldShowMLB = false
//                    }
                }
                
                Toggle(isOn: $bindableAppStorage.shouldShowGolf) {
                    Label {
                        Text("Golf")
                    } icon: {
                        Image(systemName: "figure.golf")
                            .modifier(SportsTint(sport: .golf))
                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowTennis) {
                    Label {
                        Text("Tennis")
                    } icon: {
                        Image(systemName: "tennis.racket")
                            .modifier(SportsTint(sport: .tennis))
                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowRacing) {
                    Label {
                        Text("Formula 1")
                    } icon: {
                        Image(systemName: "flag.checkered.2.crossed")
                            .modifier(SportsTint(sport: .racing))
                    }
                }
                if appStorage.shouldShowSoccer {
                    NavigationLink("Show Soccer Leagues") {
                        CompetitionPage(competitions: Leagues.allCases.filter({$0.isSoccer}).map({$0.leagueName}))
                            .environment(appStorage)
                    }
                }
            } header: {
                HStack {
                    Spacer()
                    Text("Try Scoreline Pro for multiple sports")
                    Spacer()
                }
            }
            
            Section {
                MiniSubscriptionPage(subscriptionPresented: $subscriptionPresented)
            } footer: {
                Button(action: {
                    sheetType = .none
                    appStorage.shouldShowOnboarding = false
                    appStorage.recomputeEnabledSports()
                    viewModel.getInfo()
                }, label: {
                    Text("Continue")
                        .disabled(!(appStorage.shouldShowSoccer || appStorage.shouldShowMLB || appStorage.shouldShowNBA || appStorage.shouldShowNFL || appStorage.shouldShowNHL || appStorage.shouldShowGolf || appStorage.shouldShowTennis || appStorage.shouldShowRacing))
                })
                .frame(maxWidth: .infinity,alignment: .center)
                .buttonStyle(.bordered)
            }
            .sheet(isPresented: $subscriptionPresented) {
                SubscriptionSheet(subscriptionPresented: $subscriptionPresented)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("Pick Sports")
    }
}

#Preview {
    @Previewable @State var storage = UserDefaultStorage()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())
    
    PickSportPage(sheetType: .constant(.none))
        .environment(storage)
        .environment(viewModel)
}
