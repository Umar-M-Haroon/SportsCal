//
//  SportPickerSheet.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/9/26.
//

import SwiftUI
import SportsCalModel

struct SportPickerSheet: View {
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(GameViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var bindableStorage = storage

        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $bindableStorage.shouldShowNHL) {
                        Label("NHL", systemImage: "hockey.puck.fill")
                            .modifier(SportsTint(sport: .hockey))
                    }
                    Toggle(isOn: $bindableStorage.shouldShowNFL) {
                        Label("NFL", systemImage: "football.fill")
                            .modifier(SportsTint(sport: .nfl))
                    }
                    Toggle(isOn: $bindableStorage.shouldShowNBA) {
                        Label("NBA", systemImage: "basketball.fill")
                            .modifier(SportsTint(sport: .basketball))
                    }
                    Toggle(isOn: $bindableStorage.shouldShowMLB) {
                        Label("MLB", systemImage: "baseball.fill")
                            .modifier(SportsTint(sport: .mlb))
                    }
                    Toggle(isOn: $bindableStorage.shouldShowSoccer) {
                        Label("Soccer", systemImage: "soccerball")
                            .modifier(SportsTint(sport: .soccer))
                    }
                    Toggle(isOn: $bindableStorage.shouldShowGolf) {
                        Label("Golf", systemImage: "figure.golf")
                            .modifier(SportsTint(sport: .golf))
                    }
                    Toggle(isOn: $bindableStorage.shouldShowTennis) {
                        Label("Tennis", systemImage: "tennis.racket")
                            .modifier(SportsTint(sport: .tennis))
                    }
                    Toggle(isOn: $bindableStorage.shouldShowRacing) {
                        Label("Formula 1", systemImage: "flag.checkered.2.crossed")
                            .modifier(SportsTint(sport: .racing))
                    }
                }
                if storage.shouldShowSoccer {
                    Section {
                        NavigationLink("Manage Soccer Leagues") {
                            CompetitionPage(competitions: Leagues.allCases.filter({ $0.isSoccer }).map({ $0.leagueName }))
                                .environment(storage)
                        }
                    }
                }
            }
            .navigationTitle("Sports")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            storage.recomputeEnabledSports()
            viewModel.getInfo()
            viewModel.filterSports()
        }
        .presentationDetents([.medium, .large])
    }
}
