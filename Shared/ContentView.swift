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
    
    
    @State var totalGames: [Game]?
    @State var filteredGames: [Game]?
    
    @EnvironmentObject var appStorage: UserDefaultStorage
    
    @State var shouldShowSettings: Bool = false
    
    @State private var sheetType: SheetType? = nil
    
    @State var cancellable: AnyCancellable?
    
    @State var shouldShowSportsCalProAlert: Bool = false
    
    @State var teamString: String? = ""
    
    @EnvironmentObject var favorites: Favorites
    
    @State var favoriteGames: [Game] = []
    @State var networkState: NetworkState = .loading
    
    var body: some View {
        NavigationView {
            
            if let games = filteredGames?.first?.sortByDate(games: filteredGames ?? []) {
                List {
                    if !favoriteGames.isEmpty  {
                        Section {
                            ForEach(favoriteGames) { game in
                                ScheduleGameView(gameArg: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, teamStr: teamString, favorites: favorites)
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
                                ScheduleGameView(gameArg: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, teamStr: teamString, favorites: favorites)
                            }
                        } header: {
                            HStack {
                                Text("\(games.map({$0.key})[index].formatted(format: appStorage.dateFormat))")
                                    .font(.title3)
                                    .bold()
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
                        appStorage.soonestOnTop.toggle()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .accessibilityLabel("Toggle soonest game first")
                    Menu(content: {
                        if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                            Button("NBA") {
                                appStorage.switchTo(sportType: .NBA)
                                filterSports()
                            }
                            Button("NFL") {
                                appStorage.switchTo(sportType: .NFL)
                                filterSports()
                            }
                            Button("NHL") {
                                appStorage.switchTo(sportType: .NHL)
                                filterSports()
                            }
                            Button("Soccer") {
                                appStorage.switchTo(sportType: .Soccer)
                                filterSports()
                            }
                            Button("F1") {
                                appStorage.switchTo(sportType: .F1)
                                filterSports()
                            }
                            Button("MLB") {
                                appStorage.switchTo(sportType: .MLB)
                                filterSports()
                            }
                        } else {
                            VStack {
                                Toggle("NBA", isOn: appStorage.$shouldShowNBA)
                                Toggle("NFL", isOn: appStorage.$shouldShowNFL)
                                Toggle("NHL", isOn: appStorage.$shouldShowNHL)
                                Toggle("Soccer", isOn: appStorage.$shouldShowSoccer)
                                Toggle("F1", isOn: appStorage.$shouldShowF1)
                                Toggle("MLB", isOn: appStorage.$shouldShowMLB)
                            }
                        }
                        
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
                    case .onboarding:
                        OnboardingPage(sheetType: $sheetType)
                            .environmentObject(appStorage)
                    case .calendar(let eventGame):
                        if let game = eventGame {
                            makeCalendarEvent(game: game)
                        }
                    }
                }
            } else {
                VStack {
                    if networkState == .failed {
                        Text("No upcoming games")
                            .font(.title2)
                        Button("Retry") {
                            if #available(iOS 15.0, *) {
                                Task {
                                    await getData()
                                }
                            } else {
                                cancellable = NetworkHandler().handleCall()
                                    .sink { completion in
                                        switch completion {
                                        case .finished:
                                            break
                                        case .failure(let err):
                                            print(err.localizedDescription)
                                        }
                                    } receiveValue: { sports  in
                                        (totalGames, filteredGames) = sports.convertToGames()
                                    }
                            }
                        }
                    } else if networkState == .loading {
                        ProgressView()
                    }
                }
                .navigationBarTitle("SportsCal")
                .navigationBarItems(leading: Button(action: {
                    shouldShowSettings = true
                    sheetType = .settings
                }, label: {
                    Image(systemName: "gear")
                }), trailing: Menu(content: {
                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                        Text("Subscribe to check multiple sports")
                        Button("NBA") {
                            appStorage.switchTo(sportType: .NBA)
                        }
                        Button("NFL") {
                            appStorage.switchTo(sportType: .NFL)
                        }
                        Button("NHL") {
                            appStorage.switchTo(sportType: .NHL)
                        }
                        Button("Soccer") {
                            appStorage.switchTo(sportType: .Soccer)
                        }
                        Button("F1") {
                            appStorage.switchTo(sportType: .F1)
                        }
                        Button("MLB") {
                            appStorage.switchTo(sportType: .MLB)
                        }
                    } else {
                        VStack {
                            Toggle("NBA", isOn: appStorage.$shouldShowNBA)
                            Toggle("NFL", isOn: appStorage.$shouldShowNFL)
                            Toggle("NHL", isOn: appStorage.$shouldShowNHL)
                            Toggle("Soccer", isOn: appStorage.$shouldShowSoccer)
                            Toggle("F1", isOn: appStorage.$shouldShowF1)
                            Toggle("MLB", isOn: appStorage.$shouldShowMLB)
                        }
                    }
                }, label: {
                    Image(systemName: "sportscourt")
                })
                )
                .sheet(item: $sheetType) { sheetType in
                    switch sheetType {
                    case .settings:
                        
                        SettingsView(sheetType: $sheetType)
                            .environmentObject(SubscriptionManager.shared)
                    case .onboarding:
                        OnboardingPage(sheetType: $sheetType)
                    case .calendar(let eventGame):
                        if let game = eventGame {
                            makeCalendarEvent(game: game)
                        }
                    }
                }
            }
        }
        
        .onChange(of: appStorage, perform: { newValue in
            withAnimation {
                filterSports()
            }
        })
        .onChange(of: favorites, perform: { fav in
            withAnimation {
                filterSports()
            }
        })
        .alert(isPresented: $shouldShowSportsCalProAlert, content: {
            Alert(title: Text("SportsCal Pro"), message: Text("This feature requires SportsCal Pro"))
        })
        .conditionalModifier(UIDevice.current.userInterfaceIdiom == .pad, ifTrue: {$0.navigationViewStyle(StackNavigationViewStyle())}, ifFalse: {$0.navigationViewStyle(DefaultNavigationViewStyle())})
        .onAppear {
            appStorage.launches += 1
            if appStorage.launches == 5 {
                if let scene = UIApplication.shared.connectedScenes.first(where: {$0.activationState == .foregroundActive}) as? UIWindowScene {
                    SKStoreReviewController.requestReview(in: scene)
                }
            }
            if appStorage.shouldShowOnboarding {
                sheetType = .onboarding
            }
            if #available(iOS 15.0, *) {
                Task {
                    await getData()
                }
            } else {
                cancellable = NetworkHandler().handleCall()
                    .sink { completion in
                        switch completion {
                        case .finished:
                            break
                        case .failure(let err):
                            print(err.localizedDescription)
                            networkState = .failed
                        }
                    } receiveValue: { sports  in
                        (totalGames, filteredGames) = sports.convertToGames()
                        favoriteGames = sports.favoritesToGames(games: filteredGames ?? [], favorites: favorites)
                        networkState = .loaded
                    }
            }
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
    func filterSports() {
        print("⚠️ sports duration or selected sport changed, filtering")
        print("⚠️ should show F1 \(appStorage.shouldShowF1)")
        print("⚠️ should show NFL \(appStorage.shouldShowNFL)")
        print("⚠️ should show NBA \(appStorage.shouldShowNBA)")
        print("⚠️ should show NHL \(appStorage.shouldShowNHL)")
        print("⚠️ should show Soccer \(appStorage.shouldShowSoccer)")
        print("⚠️ should show MLB \(appStorage.shouldShowMLB)")
        if let first = filteredGames?.first {
            if let games = filteredGames {
                filteredGames = first.filtered(games: totalGames ?? [])
                favoriteGames = games.filter({ favorites.contains($0) })
                print(favoriteGames.count)
            }
        } else {
            filteredGames = totalGames?.first?.filtered(games: totalGames ?? [])
            favoriteGames = filteredGames?.filter({ favorites.contains($0) }) ?? []
            print(favoriteGames.count)
        }
        print("⚠️ total amount of games, \(totalGames?.count) filtered result \(filteredGames?.count)")
    }
    @available(iOS 15.0.0, *)
    func getData() async {
        //        #if DEBUG
        //        if ProcessInfo.processInfo.environment["FULL_DATA"] != nil {
        //            let data = try! Data(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "Sports", ofType: "json")!))
        //
        //
        //            let nbaData = try! JSONDecoder().decode(Sports.self, from: data)
        //            (totalGames, nbaResult) = nbaData.convertToGames()
        //        }
        //        #else
        do {
            let result = try await NetworkHandler().handleCall(year: "2020")
            (totalGames, filteredGames) = result.convertToGames()
            favoriteGames = result.favoritesToGames(games: filteredGames ?? [], favorites: favorites)
            networkState = .loaded
        } catch let e {
            print(e)
            print(e.localizedDescription)
        }
        //        #endif
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
