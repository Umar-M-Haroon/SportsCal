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
                DisclosureGroup("Show Leagues") {
                    ForEach(Leagues.allCases.filter({!$0.isSoccer}), id: \.rawValue) { league in
                        Toggle(league.leagueName, isOn: .constant(false))
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
                Button(action: {
                    sheetType = .none
                }, label: {
                    Text("Continue")
                })
                .frame(maxWidth: .infinity,alignment: .center)
                .buttonStyle(.bordered)
                .listRowSeparator(.hidden)
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
