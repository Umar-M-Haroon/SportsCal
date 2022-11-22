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
    var body: some View {
        List {
            Section {
                Toggle("NHL", isOn: appStorage.$shouldShowNHL)
                Toggle("NFL", isOn: appStorage.$shouldShowNFL)
                Toggle("NBA", isOn: appStorage.$shouldShowNBA)
                Toggle("MLB", isOn: appStorage.$shouldShowMLB)
                Toggle("Soccer", isOn: appStorage.$shouldShowSoccer)
                if appStorage.shouldShowSoccer {
                    DisclosureGroup("Show Soccer Leagues") {
                        ForEach(Leagues.allCases.filter({!$0.isSoccer}), id: \.rawValue) { league in
                            CompetitionView(competition: league.leagueName, isHidden: !appStorage.hiddenCompetitions.contains(league.leagueName))
                                .environmentObject(appStorage)
                        }
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
                }, label: {
                    Text("Continue")
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
        .onAppear {
            for league in Leagues.allCases.filter({!$0.isSoccer}) {
                appStorage.hiddenCompetitions.append(league.leagueName)
            }
        }
    }
}

struct PickSportPage_Previews: PreviewProvider {
    static var previews: some View {
        PickSportPage(sheetType: .constant(.none))
    }
}
