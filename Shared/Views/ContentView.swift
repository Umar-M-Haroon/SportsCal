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
#if canImport(ActivityKit)
import ActivityKit
#endif

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
    @Environment(\.scenePhase) var scenePhase
    
    @State var shouldShowSettings: Bool = false
    
    @State private var sheetType: SheetType? = nil
    
    @State var shouldShowSportsCalProAlert: Bool = false
    
    @State var teamString: String? = ""
    
    @EnvironmentObject var storage: UserDefaultStorage
    @EnvironmentObject var favorites: Favorites
    
    @StateObject var viewModel: GameViewModel
    
    @State var searchString: String = ""
    @State var shouldShowPromo: Bool = false
    @State var isListLayout: Bool = true
    var body: some View {
        NavigationView {
            Group {
                Section {
                    SportsSelectView(currentlyLiveSports: viewModel.currentlyLiveSports)
                        .environmentObject(viewModel)
                }  footer: {
                    if shouldShowPromo {
                        HStack {
                            Text("Try SportsCal Pro to see multiple sports at once")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Button {
                                sheetType = .settings
                            } label: {
                                Text("Learn More.")
                                    .font(.caption2)
                            }
                        }
                    }
                    if #available(iOS 16.1, *) {
                        LiveActivityStatusView()
                    }
                }
                List {
                    if !viewModel.sortedGames.isEmpty {
                        LiveEventsView(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType)
                            .environmentObject(favorites)
                            .environmentObject(storage)
                            .environmentObject(viewModel)
                        FavoriteGamesView(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType)
                            .environmentObject(favorites)
                            .environmentObject(storage)
                            .environmentObject(viewModel)
                        ForEach(viewModel.sortedGames.map({$0.key}).indices, id: \.self) { index in
                            Section {
                                ForEach(viewModel.sortedGames.map({$0.value})[index]) { game in
                                    if let (homeTeam, awayTeam) = viewModel.getTeams(for: game) {
                                        if let homeScore = Int(game.intHomeScore ?? ""), let awayScore = Int(game.intAwayScore ?? "") {
                                            GameScoreView(homeTeam: homeTeam, awayTeam: awayTeam, homeScore: homeScore, awayScore: awayScore, game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: false)
                                                .environmentObject(favorites)
                                        } else {
                                            UpcomingGameView(homeTeam: homeTeam, awayTeam: awayTeam, game: game, showCountdown: storage.$showStartTime, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, dateFormat:  storage.dateFormat)
                                                .environmentObject(favorites)
                                        }
                                    } else {
#if DEBUG
                                        VStack {
                                            Text("No game")
                                            Text(game.strHomeTeam)
                                            Text(game.strAwayTeam)
                                        }
#endif
                                    }
                                }
                            } header: {
                                HStack {
                                    Text("\(viewModel.sortedGames.map({$0.key})[index].formatted(format: viewModel.appStorage.dateFormat))")
                                        .font(.headline)
                                }
                            }
                        }
                    } else {
                        if viewModel.networkState == .loading {
                            HStack {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            }
                            .listRowBackground(Color.clear)
                        } else {
                            VStack {
                                Text("No games fetched")
                                    .foregroundColor(.secondary)
                                Button("Retry") {
                                    viewModel.getInfo()
                                }
                                .foregroundColor(Color.blue)
                            }
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .searchable(text: $searchString, placement: SearchFieldPlacement.navigationBarDrawer(displayMode: .automatic), prompt: "Teams: ")
            }
            .navigationBarTitle("SportsCal")
            .navigationBarItems(leading: Button(action: {
                shouldShowSettings = true
                sheetType = .settings
            }, label: {
                Image(systemName: "gear")
            }))
            .sheet(item: $sheetType) { sheetType in
                switch sheetType {
                case .settings:
                    SettingsView(sheetType: $sheetType)
                        .environmentObject(storage)
                        .environmentObject(viewModel)
                case .onboarding:
                    OnboardingPage(sheetType: $sheetType)
                        .environmentObject(storage)
                        .environmentObject(viewModel)
                case .calendar(let eventGame):
                    if let game = eventGame {
                        makeCalendarEvent(game: game)
                    }
                }
            }
        }
        .onChange(of: favorites.teams, perform: { _ in
            withAnimation {
                viewModel.filterSports(searchString: searchString)
            }
        })
        .onChange(of: searchString, perform: { newValue in
            withAnimation {
                viewModel.filterSports(searchString: newValue)
            }
        })
        .refreshable(action: {
            viewModel.getInfo()
        })
        .alert(isPresented: $shouldShowSportsCalProAlert, content: {
            Alert(title: Text("SportsCal Pro"), message: Text("This feature requires SportsCal Pro"))
        })
        .conditionalModifier(UIDevice.current.userInterfaceIdiom == .pad, ifTrue: {$0.navigationViewStyle(StackNavigationViewStyle())}, ifFalse: {$0.navigationViewStyle(DefaultNavigationViewStyle())})
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                viewModel.getInfo()
            }
        }
        .onAppear {
            WidgetCenter.shared.reloadAllTimelines()
            if viewModel.appStorage.launches == 5 {
                if let scene = UIApplication.shared.connectedScenes.first(where: {$0.activationState == .foregroundActive}) as? UIWindowScene {
                    SKStoreReviewController.requestReview(in: scene)
                }
            }
            if viewModel.appStorage.shouldShowOnboarding {
                sheetType = .onboarding
            }
        }
    }
    
    func makeCalendarEvent(game: Game) -> CalendarRepresentable {
        let eventStore = EKEventStore()
        print("⚠️ making calendar event for game \(game)")
        let event = EKEvent(eventStore: eventStore)
        event.title = "\(game.strAwayTeam) @ \(game.strHomeTeam)"
        if let gameDate = game.standardDate {
            event.startDate = gameDate
            event.endDate = gameDate.afterHoursFromNow(hours: 2)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites()))
            .environmentObject(UserDefaultStorage())
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
