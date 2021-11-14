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
    @AppStorage("shouldShowNBA") var shouldShowNBA: Bool = false
    @AppStorage("shouldShowNFL") var shouldShowNFL: Bool = false
    @AppStorage("shouldShowNHL") var shouldShowNHL: Bool = false
    @AppStorage("shouldShowSoccer") var shouldShowSoccer: Bool = false
    @AppStorage("shouldShowF1") var shouldShowF1: Bool = false
    @AppStorage("shouldShowMLB") var shouldShowMLB: Bool = false
    @AppStorage("shouldShowOnboarding") var shouldShowOnboarding: Bool = true
    @AppStorage("hidesPastEvents") var hidePastEvents: Bool = false
    @AppStorage("soonestOnTop") var soonestOnTop: Bool = true
    @State var shouldShowSettings: Bool = false
    
    @AppStorage("duration") var durations: Durations = .oneWeek
    
    @State private var sheetType: SheetType? = nil
    
    @State var cancellable: AnyCancellable?
    
    @State var shouldShowSportsCalProAlert: Bool = false
    
    @State var teamString: String? = ""
    
    @EnvironmentObject var favorites: Favorites
    
    var body: some View {
        NavigationView {
            if let games = filteredGames?.first?.sortByDate(games: filteredGames ?? []) {
                List {
                    ForEach(games.map({$0.key}).indices, id: \.self) { index in
                        Section {
                            ForEach(games.map({$0.value})[index]) { game in
                                ScheduleGameView(gameArg: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, teamStr: teamString, favorites: favorites)
                            }
                        } header: {
                            HStack {
                                Text("\(games.map({$0.key})[index].formatted())")
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
                        soonestOnTop.toggle()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .accessibilityLabel("Toggle soonest game first")
                    Menu(content: {
                            if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                                Button("NBA") {
                                    switchTo(sportType: .NBA)
                                }
                                Button("NFL") {
                                    switchTo(sportType: .NFL)
                                }
                                Button("NHL") {
                                    switchTo(sportType: .NHL)
                                }
                                Button("Soccer") {
                                    switchTo(sportType: .Soccer)
                                }
                                Button("F1") {
                                    switchTo(sportType: .F1)
                                }
                                Button("MLB") {
                                    switchTo(sportType: .MLB)
                                }
                            } else {
                                VStack {
                                    Toggle("NBA", isOn: $shouldShowNBA)
                                    Toggle("NFL", isOn: $shouldShowNFL)
                                    Toggle("NHL", isOn: $shouldShowNHL)
                                    Toggle("Soccer", isOn: $shouldShowSoccer)
                                    Toggle("F1", isOn: $shouldShowF1)
                                    Toggle("MLB", isOn: $shouldShowMLB)
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
                    case .calendar(let eventGame):
                        if let game = eventGame {
                            makeCalendarEvent(game: game)
                        }
                    }
                }
            } else {
                VStack {
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
                }
                .navigationBarTitle("SportsCal")
                .navigationBarItems(leading: Button(action: {
                    shouldShowSettings = true
                    sheetType = .settings
                }, label: {
                    Image(systemName: "gear")
                }), trailing: Menu(content: {
                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                        Button("NBA") {
                            switchTo(sportType: .NBA)
                        }
                        Button("NFL") {
                            switchTo(sportType: .NFL)
                        }
                        Button("NHL") {
                            switchTo(sportType: .NHL)
                        }
                        Button("Soccer") {
                            switchTo(sportType: .Soccer)
                        }
                        Button("F1") {
                            switchTo(sportType: .F1)
                        }
                        Button("MLB") {
                            switchTo(sportType: .MLB)
                        }
                    } else {
                        VStack {
                            Toggle("NBA", isOn: $shouldShowNBA)
                            Toggle("NFL", isOn: $shouldShowNFL)
                            Toggle("NHL", isOn: $shouldShowNHL)
                            Toggle("Soccer", isOn: $shouldShowSoccer)
                            Toggle("F1", isOn: $shouldShowF1)
                            Toggle("MLB", isOn: $shouldShowMLB)
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
        .navigationViewStyle(StackNavigationViewStyle())
        .onChange(of: durations, perform: { newDuration in
            withAnimation {
                
                filterSports()
            }
        })
        .onChange(of: shouldShowF1, perform: { newDuration in
            withAnimation {
                filterSports()
            }
        })
        .onChange(of: shouldShowNBA, perform: { newDuration in
            withAnimation {
                filterSports()
            }
        })
        .onChange(of: shouldShowNHL, perform: { newDuration in
            withAnimation {
                filterSports()
            }
        })
        .onChange(of: shouldShowNFL, perform: { newDuration in
            withAnimation {
                filterSports()
            }
        })
        .onChange(of: shouldShowSoccer, perform: { newDuration in
            withAnimation {
                filterSports()
            }
        })
        .onChange(of: hidePastEvents, perform: { _ in
            withAnimation {
                filterSports()
            }
        })
        .onChange(of: soonestOnTop, perform: { _ in
            withAnimation {
                filterSports()
            }
        })
        .alert(isPresented: $shouldShowSportsCalProAlert, content: {
            Alert(title: Text("SportsCal Pro"), message: Text("This feature requires SportsCal Pro"))
        })
        //        .alert("SportsCal Pro", isPresented: $shouldShowSportsCalProAlert) {
        //            Button("OK") {
        //                shouldShowSportsCalProAlert = false
        //            }
        //        }
        .onAppear {
            WidgetCenter.shared.reloadAllTimelines()
            if shouldShowOnboarding {
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
                        }
                    } receiveValue: { sports  in
                        (totalGames, filteredGames) = sports.convertToGames()
                    }
            }
        }
    }
    func switchTo(sportType: SportTypes) {
        switch sportType {
        case .NHL:
            shouldShowF1 = false
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = true
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .NFL:
            shouldShowF1 = false
            shouldShowNFL = true
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .NBA:
            shouldShowF1 = false
            shouldShowNFL = false
            shouldShowNBA = true
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .MLB:
            shouldShowF1 = false
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = true
            break
        case .F1:
            shouldShowF1 = true
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .Soccer:
            shouldShowF1 = false
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = true
            shouldShowMLB = false
            break
        }
        filterSports()
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
        print("⚠️ should show F1 \(shouldShowF1)")
        print("⚠️ should show NFL \(shouldShowNFL)")
        print("⚠️ should show NBA \(shouldShowNBA)")
        print("⚠️ should show NHL \(shouldShowNHL)")
        print("⚠️ should show Soccer \(shouldShowSoccer)")
        print("⚠️ should show MLB \(shouldShowMLB)")
        if let first = filteredGames?.first {
            if let _ = filteredGames {
                filteredGames = first.filtered(games: totalGames ?? [])
            }
        } else {
            filteredGames = totalGames?.first?.filtered(games: totalGames ?? [])
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
