//
//  OnboardingPage.swift
//  OnboardingPage
//
//  Created by Umar Haroon on 8/15/21.
//

import SwiftUI

struct OnboardingPage: View {
    @AppStorage("shouldShowNBA") var shouldShowNBA: Bool = false
    @AppStorage("shouldShowNFL") var shouldShowNFL: Bool = false
    @AppStorage("shouldShowNHL") var shouldShowNHL: Bool = false
    @AppStorage("shouldShowSoccer") var shouldShowSoccer: Bool = false
    @AppStorage("shouldShowF1") var shouldShowF1: Bool = false
    @AppStorage("shouldShowMLB") var shouldShowMLB: Bool = false
    @AppStorage("shouldShowOnboarding") var shouldShowOnboarding: Bool = true
    @Binding var sheetType: SheetType?
    var body: some View {
        VStack {

        Text("SportsCal")
                .font(.largeTitle)
                .bold()
            
            HStack {
                Image(systemName: "clock.fill")
                    .font(.title)
                VStack {
                    Text("Time filtering")
                        .font(.headline)
                    Text("Be specific with which upcoming games you want to see")
                        .font(.callout)
                }
            }
            .padding()
            HStack {
                Image(systemName: "sportscourt")
                    .font(.title)
                VStack {
                    Text("Multiple Sports")
                        .font(.headline)
                    Text("Pick which sports you want to watch")
                        .font(.callout)
                }
            }
            .padding()
            Menu("Pick a sport to start") {
                Button("F1") {
                    shouldShowF1 = true
                    shouldShowOnboarding = false
                    sheetType = nil
                }
                Button("MLB") {
                    shouldShowMLB = true
                    shouldShowOnboarding = false
                    sheetType = nil
                }
                Button("NHL") {
                    shouldShowNHL = true
                    shouldShowOnboarding = false
                    sheetType = nil
                }
                Button("NBA") {
                    shouldShowNBA = true
                    shouldShowOnboarding = false
                    sheetType = nil
                }
                Button("NFL") {
                    shouldShowNFL = true
                    shouldShowOnboarding = false
                    sheetType = nil
                }
                Button("Soccer") {
                    shouldShowSoccer = true
                    shouldShowOnboarding = false
                    sheetType = nil
                }
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
    }
}
