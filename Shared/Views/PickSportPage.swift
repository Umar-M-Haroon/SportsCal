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
    @EnvironmentObject var appStorage: UserDefaultStorage
    @Binding var sheetType: SheetType?
    @EnvironmentObject var viewModel: GameViewModel
    var body: some View {
        List {
            Section {
                Toggle(isOn: appStorage.$shouldShowNHL) {
                    Label {
                        Text("NHL")
                    } icon: {
                        Image(systemName: "hockey.puck.fill")
                            .modifier(SportsTint(sport: .hockey))
                    }
                }
                .onTapGesture {
                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                        //                            appStorage.switchTo(sportType: .hockey)
                        appStorage.shouldShowNFL = false
                        appStorage.shouldShowNBA = false
                        appStorage.shouldShowNHL.toggle()
                        appStorage.shouldShowSoccer = false
                        appStorage.shouldShowMLB = false
                    }
                }
                Toggle(isOn: appStorage.$shouldShowNFL) {
                    Label {
                        Text("NFL")
                    } icon: {
                        Image(systemName: "football.fill")
                            .modifier(SportsTint(sport: .nfl))
                    }
                }
                .onTapGesture {
                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                        appStorage.shouldShowNFL.toggle()
                        appStorage.shouldShowNBA = false
                        appStorage.shouldShowNHL = false
                        appStorage.shouldShowSoccer = false
                        appStorage.shouldShowMLB = false
                    }
                }
                Toggle(isOn: appStorage.$shouldShowNBA) {
                    Label {
                        Text("NBA")
                    } icon: {
                        Image(systemName: "basketball.fill")
                            .modifier(SportsTint(sport: .basketball))
                    }
                }
                .onTapGesture {
                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                        appStorage.shouldShowNFL = false
                        appStorage.shouldShowNBA.toggle()
                        appStorage.shouldShowNHL = false
                        appStorage.shouldShowSoccer = false
                        appStorage.shouldShowMLB = false
                    }
                }
                Toggle(isOn: appStorage.$shouldShowMLB) {
                    Label {
                      Text("MLB")
                    } icon: {
                        Image(systemName: "baseball.fill")
                            .modifier(SportsTint(sport: .mlb))
                    }
                }
                .onTapGesture {
                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                        appStorage.shouldShowNFL = false
                        appStorage.shouldShowNBA = false
                        appStorage.shouldShowNHL = false
                        appStorage.shouldShowSoccer = false
                        appStorage.shouldShowMLB.toggle()
                    }
                }
                Toggle(isOn: appStorage.$shouldShowSoccer) {
                    Label {
                        Text("Soccer")
                    } icon: {
                        Image(systemName: "soccerball")
                            .modifier(SportsTint(sport: .soccer))
                    }
                }
                .onTapGesture {
                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                        appStorage.shouldShowNFL = false
                        appStorage.shouldShowNBA = false
                        appStorage.shouldShowNHL = false
                        appStorage.shouldShowSoccer.toggle()
                        appStorage.shouldShowMLB = false
                    }
                }
                
                if appStorage.shouldShowSoccer {
                    NavigationLink("Show Soccer Leagues") {
                        CompetitionPage(competitions: Leagues.allCases.filter({$0.isSoccer}).map({$0.leagueName}))
                            .environmentObject(appStorage)
                    }
                }
            } header: {
                HStack {
                    Spacer()
                    Text("Try SportsCal Pro for multiple sports")
                    Spacer()
                }
            }
            
            Section {
                MiniSubscriptionPage(subscriptionPresented: $subscriptionPresented)
            } footer: {
                Button(action: {
                    sheetType = .none
                    appStorage.shouldShowOnboarding = false
                    viewModel.getInfo()
                }, label: {
                    Text("Continue")
                        .disabled(!(appStorage.shouldShowSoccer || appStorage.shouldShowMLB || appStorage.shouldShowNBA || appStorage.shouldShowNFL || appStorage.shouldShowNHL))
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

struct PickSportPage_Previews: PreviewProvider {
    static var previews: some View {
        PickSportPage(sheetType: .constant(.none))
    }
}
