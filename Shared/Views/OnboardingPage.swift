//
//  OnboardingPage.swift
//  OnboardingPage
//
//  Created by Umar Haroon on 8/15/21.
//

import SwiftUI
import SportsCalModel

struct OnboardingPage: View {
    @EnvironmentObject var appStorage: UserDefaultStorage
    @Binding var sheetType: SheetType?
    var body: some View {
        NavigationView {
                VStack(alignment: .leading) {
                    InfoView(title: "Favorites", subTitle: "Easily Check when your favorite team plays ", image: Image(systemName: "star.fill"), tint: .yellow)
                    InfoView(title: "Notifications", subTitle: "Be notified when the game is about to start", image: Image(systemName: "app.badge.fill"), tint: .red)
                    InfoView(title: "Multiple Sports", subTitle: "Check multiple sports at a glance", image: Image(systemName: "sportscourt.fill"), tint: .green)
                    InfoView(title: "Live Activities", subTitle: "See games from anywhere with Live Activities", image: Image(systemName: "clock.badge.fill"), tint: .blue)
                    Spacer()
                    Button {
                    } label: {
                        ZStack {
                            NavigationLink(destination: PickSportPage(sheetType: $sheetType)
                                .environmentObject(appStorage)
                            ) {
                                
                                
                                Text("Next")
                                    .frame(maxWidth: .infinity)
                                    .padding(4)
                            }
                            Text("Next")
                                .frame(maxWidth: .infinity)
                                .padding(4)
                        }
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                        .padding()
                }
                .navigationTitle("Welcome to SportsCal!")
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

struct OnboardingPage_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPage(sheetType: Binding(get: {
            .onboarding
        }, set: { val in
            val
        }))
        .environmentObject(UserDefaultStorage())
    }
}
