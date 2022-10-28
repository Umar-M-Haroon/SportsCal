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
        VStack {
        Text("Welcome to SportsCal!")
                .font(.largeTitle)
                .bold()
                .padding(.top, 20)
            Spacer()
            VStack(alignment: .leading) {
                InfoView(title: "Favorites", subTitle: "Easily Check when your favorite team plays ", image: Image(systemName: "star.fill"), tint: .yellow)
                InfoView(title: "Notifications", subTitle: "Be notified when the game is about to start", image: Image(systemName: "app.badge.fill"), tint: .red)
                InfoView(title: "Multiple Sports", subTitle: "Check multiple sports at a glance", image: Image(systemName: "sportscourt"), tint: .green)
            }
            Spacer()
           
            if #available(iOS 15.0, *) {
                Button {
                    
                } label: {
                    sportPicker()
                    .foregroundColor(.white)
                }.buttonStyle(BorderedProminentButtonStyle())
                    .tint(.green)
            } else {
                sportPicker()
            }

        }
        .padding([.bottom, .top], 30)
    }
    
    func sportPicker() -> some View {
        Menu("Pick a sport") {
            Button("F1") {
                appStorage.shouldShowF1 = true
                appStorage.shouldShowOnboarding = false
                sheetType = nil
            }
            Button("MLB") {
                appStorage.shouldShowMLB = true
                appStorage.shouldShowOnboarding = false
                sheetType = nil
            }
            Button("NHL") {
                appStorage.shouldShowNHL = true
                appStorage.shouldShowOnboarding = false
                sheetType = nil
            }
            Button("NBA") {
                appStorage.shouldShowNBA = true
                appStorage.shouldShowOnboarding = false
                sheetType = nil
            }
            Button("NFL") {
                appStorage.shouldShowNFL = true
                appStorage.shouldShowOnboarding = false
                sheetType = nil
            }
            Button("Soccer") {
                appStorage.shouldShowSoccer = true
                appStorage.shouldShowOnboarding = false
                sheetType = nil
            }
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
            }
        }
    }
}

struct OnboardingPage_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            OnboardingPage(sheetType: Binding(get: {
                .onboarding
            }, set: { val in
                val
        }))
            OnboardingPage(sheetType: Binding(get: {
                .onboarding
            }, set: { val in
                val
            }))
                .previewDevice("iPhone 12 Pro")
        }
    }
}
