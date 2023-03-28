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
                Toggle("NHL", isOn: appStorage.$shouldShowNHL)
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
                Toggle("NFL", isOn: appStorage.$shouldShowNFL)
                    .onTapGesture {
                        if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                            appStorage.shouldShowNFL.toggle()
                            appStorage.shouldShowNBA = false
                            appStorage.shouldShowNHL = false
                            appStorage.shouldShowSoccer = false
                            appStorage.shouldShowMLB = false
                        }
                    }
                Toggle("NBA", isOn: appStorage.$shouldShowNBA)
                    .onTapGesture {
                        if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                            appStorage.shouldShowNFL = false
                            appStorage.shouldShowNBA.toggle()
                            appStorage.shouldShowNHL = false
                            appStorage.shouldShowSoccer = false
                            appStorage.shouldShowMLB = false
                        }
                    }
                Toggle("MLB", isOn: appStorage.$shouldShowMLB)
                    .onTapGesture {
                        if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                            appStorage.shouldShowNFL = false
                            appStorage.shouldShowNBA = false
                            appStorage.shouldShowNHL = false
                            appStorage.shouldShowSoccer = false
                            appStorage.shouldShowMLB.toggle()
                        }
                    }
                Toggle("Soccer", isOn: appStorage.$shouldShowSoccer)
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
                        CompetitionPage(competitions: Leagues.allCases.filter({!$0.isSoccer}).map({$0.leagueName}))
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
