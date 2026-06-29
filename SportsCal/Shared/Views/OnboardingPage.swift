//
//  OnboardingPage.swift
//  OnboardingPage
//
//  Created by Umar Haroon on 8/15/21.
//

import SwiftUI
import SportsCalModel
import UserNotifications

struct OnboardingPage: View {
    @Environment(UserDefaultStorage.self) private var appStorage
    @Binding var sheetType: SheetType?
    @Environment(GameViewModel.self) private var viewModel
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                InfoView(title: "Favorites", subTitle: "Easily Check when your favorite team plays ", image: Image(systemName: "star.fill"), tint: .yellow)
                InfoView(title: "Notifications", subTitle: "Be notified when the game is about to start", image: Image(systemName: "app.badge.fill"), tint: .red)
                InfoView(title: "Multiple Sports", subTitle: "Check multiple sports at a glance", image: Image(systemName: "sportscourt.fill"), tint: .green)
                InfoView(title: "Live Activities", subTitle: "See games from anywhere with Live Activities", image: Image(systemName: "clock.badge.fill"), tint: .blue)
                InfoView(title: "World Cup 2026", subTitle: "Follow every match, group, and the road to the final", image: Image(systemName: "soccerball"), tint: Color.app(.soccer))
                Spacer()
                Button {
                    appStorage.shouldShowWorldCup = true
                    appStorage.recomputeEnabledSports()
                    viewModel.filterSports(force: true)
                    viewModel.getInfo()
                    finishOnboarding()
                } label: {
                    Label("Follow the World Cup", systemImage: "soccerball")
                        .frame(maxWidth: .infinity)
                        .padding(4)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .tint(Color.app(.soccer))
                .padding(.horizontal)
                NavigationLink {
                    PickSportPage(sheetType: $sheetType)
                        .environment(appStorage)
                        .environment(viewModel)
                } label: {
                    Text("Pick sports manually")
                        .frame(maxWidth: .infinity)
                        .padding(4)
                }
                .buttonStyle(BorderedButtonStyle())
                .padding([.horizontal, .bottom])
            }
            .navigationTitle("Welcome to Scoreline!")
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    /// Completes onboarding and, at this peak-intent moment, offers the Pro trial
    /// once (throttled + Pro-guarded by the coordinator). Falls back to simply
    /// dismissing the sheet when the offer isn't shown.
    private func finishOnboarding() {
        appStorage.shouldShowOnboarding = false
        requestNotifications()
        let offered = UpsellCoordinator.shared.request(.postOnboarding) {
            sheetType = .paywall
        }
        if !offered { sheetType = .none }
    }

    /// Contextual notification opt-in — the reason most users install a sports
    /// app. Asked here (after they've expressed intent) rather than cold at first
    /// launch, which converts much better.
    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted { MonetizationTelemetry.activationNotificationsEnabled() }
        }
    }
}

struct InfoView: View {
    var title: String
    var subTitle: String
    var image: Image
    var tint: Color
    var body: some View {
        HStack {
            image
                .font(.largeTitle)
                .frame(width: 50, height: 50, alignment: .center)
                .foregroundColor(tint)
                .padding()
                
            VStack(alignment: .leading) {
                Text(title)
                    .font(.title2)
                    .bold()
                Text(subTitle)
                    .font(.title3)
                    .lineLimit(nil)
            }
        }
    }
}

#Preview {
    @Previewable @State var storage = UserDefaultStorage()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())
    
    OnboardingPage(sheetType: Binding(get: {
        .onboarding
    }, set: { _ in
        
    }))
    .environment(storage)
    .environment(viewModel)
}
