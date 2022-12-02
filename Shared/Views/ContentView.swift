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
    var body: some View {
        NavigationView {
            Group {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(SportType.allCases, id: \.self) { sport in
                                SportsFilterView(sport: sport, shouldShowPromoCount: $shouldShowPromo, appStorage: storage)
                            }
                        }
                    }
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
                }


                if let games = viewModel.sortedGames, !games.isEmpty {
                    List {
                        if let liveEvents = viewModel.liveEvents, !liveEvents.isEmpty {
                            Section {
                                ForEach(liveEvents) { event in
                                    if let homeScore = Int(event.intHomeScore ?? ""), let awayScore = Int(event.intAwayScore ?? ""), let homeTeam = Team.getTeamInfoFrom(teams: viewModel.teams, teamID: event.idHomeTeam), let awayTeam = Team.getTeamInfoFrom(teams: viewModel.teams, teamID: event.idAwayTeam) {
                                        GameScoreView(homeTeam: homeTeam, awayTeam: awayTeam, homeScore: homeScore, awayScore: awayScore, game: event, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: true)
                                    }
                                }
                            } header: {
                                LiveAnimatedView()
                            }
                        }
                        if let favoriteGames = viewModel.favoriteGames, !favoriteGames.isEmpty {
                            Section {
                                ForEach(favoriteGames) { game in
                                    if let homeTeam = Team.getTeamInfoFrom(teams: viewModel.teams, teamID: game.idHomeTeam), let awayTeam = Team.getTeamInfoFrom(teams: viewModel.teams, teamID: game.idAwayTeam) {
                                        UpcomingGameView(homeTeam: homeTeam, awayTeam: awayTeam, game: game, showCountdown: storage.$showStartTime, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, dateFormat:  storage.dateFormat, isFavorite: true)
                                            .environmentObject(favorites)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text("Favorites")
                                        .font(.headline)
                                }
                            }
                        }
                        ForEach(games.map({$0.key}).indices, id: \.self) { index in
                            Section {
                                ForEach(games.map({$0.value})[index]) { game in
                                    if let homeTeam = Team.getTeamInfoFrom(teams: viewModel.teams, teamID: game.idHomeTeam), let awayTeam = Team.getTeamInfoFrom(teams: viewModel.teams, teamID: game.idAwayTeam) {
                                        if let homeScore = Int(game.intHomeScore ?? ""), let awayScore = Int(game.intAwayScore ?? "") {
                                            GameScoreView(homeTeam: homeTeam, awayTeam: awayTeam, homeScore: homeScore, awayScore: awayScore, game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: false)
                                                .environmentObject(favorites)
                                        } else {
                                            UpcomingGameView(homeTeam: homeTeam, awayTeam: awayTeam, game: game, showCountdown: storage.$showStartTime, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, dateFormat:  storage.dateFormat)
                                                .environmentObject(favorites)
                                        }
                                    }
                                }
                            } header: {
                                HStack {
                                    Text("\(games.map({$0.key})[index].formatted(format: viewModel.appStorage.dateFormat))")
                                        .font(.headline)
                                }
                            }
                        }
                    }
                } else {
                    VStack {
                        if viewModel.networkState == .loading {
                            ProgressView()
                        } else if viewModel.networkState == .failed {
                            Text("No games fetched")
                                .font(.title2)
                            Button("Retry") {
                                viewModel.getInfo()
                            }
                        }
                    }
                Spacer()
                }

            }
            .searchable(text: $searchString, placement: SearchFieldPlacement.navigationBarDrawer(displayMode: .automatic), prompt: "Teams: ")
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
                case .onboarding:
                    OnboardingPage(sheetType: $sheetType)
                        .environmentObject(storage)
                case .calendar(let eventGame):
                    if let game = eventGame {
                        makeCalendarEvent(game: game)
                    }
                }
            }
        }
        .onChange(of: storage.shouldShowMLB, perform: { _ in
            withAnimation {
                viewModel.filterSports(searchString: searchString)
            }
        })
        .onChange(of: storage.shouldShowNHL, perform: { _ in
            withAnimation {
                viewModel.filterSports(searchString: searchString)
            }
        })
        .onChange(of: storage.shouldShowNBA, perform: { _ in
            withAnimation {
                viewModel.filterSports(searchString: searchString)
            }
        })
        .onChange(of: storage.shouldShowNFL, perform: { _ in
            withAnimation {
                viewModel.filterSports(searchString: searchString)
            }
        })
        .onChange(of: storage.soonestOnTop, perform: { _ in
            withAnimation {
                viewModel.filterSports(searchString: searchString)
            }
        })
        .onChange(of: storage.shouldShowSoccer, perform: { _ in
            withAnimation {
                viewModel.filterSports(searchString: searchString)
            }
        })
        .onChange(of: storage.hidePastEvents, perform: { _ in
            withAnimation {
                viewModel.filterSports(searchString: searchString)
            }
        })
        .onChange(of: storage.durations, perform: { _ in
            withAnimation {
                viewModel.filterSports(searchString: searchString)
            }
        })
        .onChange(of: favorites.teams, perform: { _ in
            withAnimation {
                viewModel.filterSports(searchString: searchString)
            }
        })
        .onChange(of: storage.hiddenCompetitions, perform: { _ in
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
            viewModel.appStorage.launches += 1
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
        if let gameDate = game.getDate() {
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
