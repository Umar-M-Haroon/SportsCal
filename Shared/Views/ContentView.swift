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
    
    @State var shouldShowPromo: Bool = false
    @State var isListLayout: Bool = true
    var body: some View {
        NavigationView {
            showAppropriateLaunchScreen()
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
    
    func showAppropriateLaunchScreen() -> some View {
        if #available(iOS 16.0, *) {
           return TabView {
                ListPage(shouldShowPromo: shouldShowPromo, shouldShowSportsCalProAlert: shouldShowSportsCalProAlert, shouldShowSettings: shouldShowSettings)
                    .environmentObject(viewModel)
                    .environmentObject(storage)
                    .environmentObject(favorites)
                    .tabItem {
                        Label("Upcoming", systemImage: "sportscourt")
                    }
                CalendarViewRepresentable()
                    .environmentObject(viewModel)
                    .tabItem {
                        Label("calendar", systemImage: "calendar")
                    }
            }
        } else {
            return EmptyView()
        }
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
