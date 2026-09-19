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

    @State private var sports: [SportType] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sports, id: \.self) { sport in
                        Toggle(isOn: Binding(
                            get: { storage.effectiveShouldShow(sport) },
                            set: { storage.toggleSport(sport, enabled: $0) }
                        )) {
                            Label(sport.displayName, systemImage: sport.systemImage)
                                .modifier(SportsTint(sport: sport))
                        }
                        if storage.effectiveShouldShow(sport) {
                            Toggle(isOn: Binding(
                                get: { storage.favoritesOnly(for: sport) },
                                set: { storage.setFavoritesOnly(sport, value: $0) }
                            )) {
                                Label("Favorites only", systemImage: "star.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 28)
                            if EventCoverage.sports.contains(sport) {
                                coveragePicker(for: sport)
                                    .padding(.leading, 28)
                            }
                        }
                    }
                    .onMove { from, to in
                        sports.move(fromOffsets: from, toOffset: to)
                        storage.sportOrder = sports.map(\.rawValue)
                        storage.recomputeEnabledSports()
                    }
                }
                if storage.shouldShowSoccer {
                    Section {
                        #if os(macOS)
                        DisclosureGroup("Manage Soccer Leagues") {
                            ForEach(Leagues.allCases.filter({ $0.isSoccer }), id: \.self) { league in
                                CompetitionView(league: league, isShown: !storage.hiddenCompetitions.contains(league.leagueName))
                                    .environment(storage)
                            }
                        }
                        #else
                        NavigationLink("Manage Soccer Leagues") {
                            CompetitionPage(competitions: Leagues.allCases.filter({ $0.isSoccer }))
                                .environment(storage)
                        }
                        #endif
                    }
                }
                if storage.shouldShowNBA {
                    Section {
                        #if os(macOS)
                        DisclosureGroup("Manage Basketball Leagues") {
                            ForEach(Leagues.allCases.filter({ $0.isBasketball }), id: \.self) { league in
                                CompetitionView(league: league, isShown: !storage.hiddenCompetitions.contains(league.leagueName))
                                    .environment(storage)
                            }
                        }
                        #else
                        NavigationLink("Manage Basketball Leagues") {
                            CompetitionPage(competitions: Leagues.allCases.filter({ $0.isBasketball }))
                                .environment(storage)
                        }
                        #endif
                    }
                }
            }
            .navigationTitle("Sports")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .cancellationAction) {
                    EditButton()
                }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            sports = storage.orderedSports
        }
        .onDisappear {
            storage.recomputeEnabledSports()
            viewModel.getInfo()
            viewModel.filterSports()
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 350, minHeight: 400)
        #endif
    }

    /// Grand Slams / big events / everything for tennis and golf.
    private func coveragePicker(for sport: SportType) -> some View {
        // The coverage props are @ObservationIgnored; setCoverage bumps this tracked counter.
        _ = storage.preferenceVersion
        let selection = Binding(
            get: { storage.coverage(for: sport) },
            set: { storage.setCoverage($0, for: sport) }
        )
        return VStack(alignment: .leading, spacing: 2) {
            Picker(selection: selection) {
                ForEach(EventCoverage.allCases, id: \.self) { coverage in
                    Text(coverage.displayName(for: sport)).tag(coverage)
                }
            } label: {
                Label("Show", systemImage: "trophy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .pickerStyle(.menu)
            Text(selection.wrappedValue.summary(for: sport))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
