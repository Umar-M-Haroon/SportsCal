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
    @Environment(Favorites.self) private var favorites
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    hero
                    VStack(spacing: 8) {
                        Text("Welcome to Scoreline")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("Every game you care about, in one place.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        OnboardingFeatureRow(systemImage: "calendar", tint: .red,
                                             title: "One schedule for every league",
                                             detail: "The NFL to the Premier League, cricket to F1.")
                        OnboardingFeatureRow(systemImage: "bolt.fill", tint: .orange,
                                             title: "Live on your Lock Screen",
                                             detail: "Scores and big moments with Live Activities and widgets.")
                        OnboardingFeatureRow(systemImage: "star.fill", tint: .yellow,
                                             title: "Built around your teams",
                                             detail: "Follow teams for reminders, alerts and a personal feed.")
                    }
                    .frame(maxWidth: 480, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    NavigationLink {
                        pickSportPage
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(6)
                    }
                    .buttonStyle(.borderedProminent)
                    if WorldCupSeason.isActive {
                        Button {
                            appStorage.shouldShowWorldCup = true
                            appStorage.recomputeEnabledSports()
                            viewModel.filterSports(force: true)
                            viewModel.getInfo()
                            finishOnboarding()
                        } label: {
                            Label("Just follow the World Cup", systemImage: "soccerball")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding()
                .background(.bar)
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
        // A fixed window-like size on macOS: min-only frames let the sheet open
        // at the cramped minimum, which reads as a misplaced phone modal. On
        // iPhone the sheet already fills the screen, and the iPhone Duo's outer
        // display is 466pt tall in landscape, so no floor there.
        #if os(macOS)
        .frame(width: 640, height: 560)
        #endif
        .onAppear { MonetizationTelemetry.onboardingStarted() }
    }

    private var pickSportPage: some View {
        PickSportPage(sheetType: $sheetType)
            .environment(appStorage)
            .environment(viewModel)
            .environment(favorites)
    }

    /// Sport symbols in their colours, fanned around the app's name.
    private var hero: some View {
        HStack(spacing: -10) {
            ForEach([(SportType.nfl, "football.fill"), (.basketball, "basketball.fill"), (.soccer, "soccerball"),
                     (.mlb, "baseball.fill"), (.hockey, "hockey.puck.fill")], id: \.1) { sport, symbol in
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color.app(sport)))
                    .overlay(Circle().stroke(.background, lineWidth: 3))
            }
        }
        .accessibilityHidden(true)
    }

    /// Completes onboarding and, at this peak-intent moment, offers the Pro trial
    /// once (throttled + Pro-guarded by the coordinator). Falls back to simply
    /// dismissing the sheet when the offer isn't shown.
    private func finishOnboarding() {
        appStorage.shouldShowOnboarding = false
        MonetizationTelemetry.onboardingCompleted(sportCount: appStorage.enabledSports.count)
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
            if granted {
                MonetizationTelemetry.activationNotificationsEnabled()
                NotificationManager.registerForRemoteNotificationsAfterGrant()
            }
            MonetizationTelemetry.notificationsResolved(granted: granted)
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
    .environment(Favorites())
}
