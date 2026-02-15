//
//  OnboardingPage.swift
//  OnboardingPage
//
//  Created by Umar Haroon on 8/15/21.
//

import SwiftUI
import SportsCalModel

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
                Spacer()
                NavigationLink {
                    PickSportPage(sheetType: $sheetType)
                        .environment(appStorage)
                        .environment(viewModel)
                } label: {
                    Text("Next")
                        .frame(maxWidth: .infinity)
                        .padding(4)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .padding()
            }
            .navigationTitle("Welcome to SportsCal!")
        }
        .frame(minWidth: 400, minHeight: 500)
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
