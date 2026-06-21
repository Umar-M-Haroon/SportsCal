//
//  PickSportPage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/19/22.
//

import SwiftUI
import SportsCalModel
import UserNotifications
struct PickSportPage: View {
    @State var subscriptionPresented: Bool = false
    @Environment(UserDefaultStorage.self) private var appStorage
    @Binding var sheetType: SheetType?
    @Environment(GameViewModel.self) private var viewModel
    var body: some View {
        @Bindable var bindableAppStorage = appStorage
        
        List {
            Section {
                Toggle(isOn: $bindableAppStorage.shouldShowWorldCup) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FIFA World Cup 2026")
                            Text("Jun 11 – Jul 19 · follow every match")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "soccerball")
                            .modifier(SportsTint(sport: .soccer))
                    }
                }
            } header: {
                Text("Featured")
            } footer: {
                Text("Turn this on to follow the World Cup without enabling all of soccer.")
            }

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
                Toggle(isOn: $bindableAppStorage.shouldShowWNBA) {
                    Label {
                        Text("WNBA")
                    } icon: {
                        Image(systemName: "basketball.fill")
                            .modifier(SportsTint(sport: .basketball))
                    }
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
                        CompetitionPage(competitions: Leagues.allCases.filter({$0.isSoccer}))
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
                    appStorage.shouldShowOnboarding = false
                    appStorage.recomputeEnabledSports()
                    viewModel.getInfo()
                    requestNotifications()
                    // Peak-intent moment: offer the Pro trial once (throttled +
                    // Pro-guarded). Falls back to dismissing if not shown.
                    let offered = UpsellCoordinator.shared.request(.postOnboarding) {
                        sheetType = .paywall
                    }
                    if !offered { sheetType = .none }
                }, label: {
                    Text("Continue")
                        .disabled(!(appStorage.shouldShowSoccer || appStorage.shouldShowWorldCup || appStorage.shouldShowMLB || appStorage.shouldShowNBA || appStorage.shouldShowWNBA || appStorage.shouldShowNFL || appStorage.shouldShowNHL || appStorage.shouldShowGolf || appStorage.shouldShowTennis || appStorage.shouldShowRacing))
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

    /// Contextual notification opt-in, asked after the user has picked sports.
    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted { MonetizationTelemetry.activationNotificationsEnabled() }
        }
    }
}

#Preview {
    @Previewable @State var storage = UserDefaultStorage()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())
    
    PickSportPage(sheetType: .constant(.none))
        .environment(storage)
        .environment(viewModel)
}
