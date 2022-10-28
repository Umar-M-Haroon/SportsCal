//
//  ContentView.swift
//  Shared
//
//  Created by Umar Haroon on 7/2/21.
//

import SwiftUI
import Combine
import EventKit
import WidgetKit
import StoreKit
import SportsCalModel

enum SheetType: Identifiable {
    var id: String {
        switch self {
        case .settings:
            return "settings"
        case .onboarding:
            return "onboarding"
        case .calendar(_):
            return "calendar"
        }
    }
    case settings, onboarding
    case calendar(game: Game?)
}
struct ContentView: View {
    
    @State var shouldShowSettings: Bool = false
    
    @State private var sheetType: SheetType? = nil
    
    @State var shouldShowSportsCalProAlert: Bool = false
    
    @State var teamString: String? = ""
    
    @EnvironmentObject var favorites: Favorites
    
    @EnvironmentObject var viewModel: GameViewModel
    
    var body: some View {
        NavigationView {
            Group {
                if let games = viewModel.filteredGames?.first?.sortByDate(games: viewModel.filteredGames ?? []) {
                    List {
                        if !viewModel.favoriteGames.isEmpty  {
                            Section {
                                ForEach(viewModel.favoriteGames) { game in
                                    ScheduleGameView(gameArg: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, teamStr: teamString, favorites: viewModel.favorites, shouldSetStartTime: viewModel.appStorage.$showStartTime)
                                        .environmentObject(viewModel.favorites)
                                }
                            } header: {
                                HStack {
                                    Text("Favorites")
                                        .font(.title3)
                                        .bold()
                                }
                            }
                        }
                        ForEach(games.map({$0.key}).indices, id: \.self) { index in
                            Section {
                                ForEach(games.map({$0.value})[index]) { game in
                                    ScheduleGameView(gameArg: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, teamStr: teamString, favorites: viewModel.favorites, shouldSetStartTime: viewModel.appStorage.$showStartTime)
                                }
                            } header: {
                                HStack {
                                    Text("\(games.map({$0.key})[index].formatted(format: viewModel.appStorage.dateFormat))")
                                        .font(.title3)
                                        .bold()
                                }
                            }
                        }
                    }
                } else {
                    VStack {
                        if viewModel.networkState == .loading {
                            ProgressView()
                        } else {
                            Text("No games fetched")
                                .font(.title2)
                            Button("Retry") {
                                viewModel.getInfo()
                            }
                        }
                    }
                    
                }
            }
            .navigationBarTitle("SportsCal")
            .navigationBarItems(leading: Button(action: {
                shouldShowSettings = true
                sheetType = .settings
            }, label: {
                Image(systemName: "gear")
            }), trailing:
                                    HStack {
                Button {
                    viewModel.appStorage.soonestOnTop.toggle()
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .accessibilityLabel("Toggle soonest game first")
                Menu(content: {
//                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                        Button("NBA") {
                            viewModel.appStorage.switchTo(sportType: .NBA)
                            viewModel.filterSports()
                        }
                        Button("NFL") {
                            viewModel.appStorage.switchTo(sportType: .NFL)
                            viewModel.filterSports()
                        }
                        Button("NHL") {
                            viewModel.appStorage.switchTo(sportType: .NHL)
                            viewModel.filterSports()
                        }
                        Button("Soccer") {
                            viewModel.appStorage.switchTo(sportType: .Soccer)
                            viewModel.filterSports()
                        }
                        Button("F1") {
                            viewModel.appStorage.switchTo(sportType: .F1)
                            viewModel.filterSports()
                        }
                        Button("MLB") {
                            viewModel.appStorage.switchTo(sportType: .MLB)
                            viewModel.filterSports()
                        }
//                    } else {
//                        VStack {
//                            Toggle("NBA", isOn: viewModel.appStorage.$shouldShowNBA)
//                            Toggle("NFL", isOn: viewModel.appStorage.$shouldShowNFL)
//                            Toggle("NHL", isOn: viewModel.appStorage.$shouldShowNHL)
//                            Toggle("Soccer", isOn: viewModel.appStorage.$shouldShowSoccer)
//                            Toggle("F1", isOn: viewModel.appStorage.$shouldShowF1)
//                            Toggle("MLB", isOn: viewModel.appStorage.$shouldShowMLB)
//                        }
//                    }
                    
                }, label: {
                    Image(systemName: "sportscourt")
                })
                .accessibility(label: Text("Filter Sports"))
            }
            )
            .sheet(item: $sheetType) { sheetType in
                switch sheetType {
                case .settings:
                    SettingsView(sheetType: $sheetType)
                        .environmentObject(SubscriptionManager.shared)
                        .environmentObject(viewModel.appStorage)
                case .onboarding:
                    OnboardingPage(sheetType: $sheetType)
                case .calendar(let eventGame):
                    if let game = eventGame {
                        makeCalendarEvent(game: game)
                    }
                }
            }
        }
        .onChange(of: viewModel.appStorage, perform: { newValue in
            withAnimation {
                viewModel.filterSports()
            }
        })
        .onChange(of: viewModel.favorites, perform: { fav in
            withAnimation {
                viewModel.filterSports()
            }
        })
        .alert(isPresented: $shouldShowSportsCalProAlert, content: {
            Alert(title: Text("SportsCal Pro"), message: Text("This feature requires SportsCal Pro"))
        })
        .conditionalModifier(UIDevice.current.userInterfaceIdiom == .pad, ifTrue: {$0.navigationViewStyle(StackNavigationViewStyle())}, ifFalse: {$0.navigationViewStyle(DefaultNavigationViewStyle())})
        .onAppear {
//            viewModel.appStorage.launches += 1
//            if viewModel.appStorage.launches == 5 {
//                if let scene = UIApplication.shared.connectedScenes.first(where: {$0.activationState == .foregroundActive}) as? UIWindowScene {
//                    SKStoreReviewController.requestReview(in: scene)
//                }
//            }
//            if viewModel.appStorage.shouldShowOnboarding {
//                sheetType = .onboarding
//            }
            viewModel.getInfo()
        }
    }
    
    func makeCalendarEvent(game: Game) -> CalendarRepresentable {
        let eventStore = EKEventStore()
        print("⚠️ making calendar event for game \(game)")
        let event = EKEvent(eventStore: eventStore)
        if game.sport == .F1 {
            event.title = game.home
        } else {
            event.title = "\(game.home) @ \(game.away)"
        }
        event.startDate = game.gameDate
        event.endDate = game.gameDate.afterHoursFromNow(hours: 2)
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
        //            .environment(\.sizeCategory, .accessibilityLarge)
    }
}
extension View {
    typealias ContentTransform<Content: View> = (Self) -> Content
    
    @ViewBuilder
    func conditionalModifier<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        ifTrue: ContentTransform<TrueContent>,
        ifFalse: ContentTransform<FalseContent>
    ) -> some View {
        if condition {
            ifTrue(self)
        } else {
            ifFalse(self)
        }
    }
}
