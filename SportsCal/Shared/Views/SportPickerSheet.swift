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
                            if leagues(for: sport).count > 1 {
                                leagueManager(for: sport)
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

    /// Every league this sport covers, in enum order. One league (NFL, NHL, MLB, F1)
    /// means there is nothing to choose between, so the row is left off.
    private func leagues(for sport: SportType) -> [Leagues] {
        Leagues.allCases.filter { SportType(league: $0) == sport }
    }

    /// Per-sport competition visibility, inline under the sport it belongs to. These used
    /// to be separate top-level Settings sections ("Visible soccer competitions", …), one
    /// per sport, sitting far from the sport's own switches.
    @ViewBuilder
    private func leagueManager(for sport: SportType) -> some View {
        let sportLeagues = leagues(for: sport)
        let hiddenCount = sportLeagues.filter { storage.hiddenCompetitions.contains($0.leagueName) }.count
        #if os(macOS)
        DisclosureGroup("Leagues") {
            ForEach(sportLeagues, id: \.self) { league in
                CompetitionView(league: league, isShown: !storage.hiddenCompetitions.contains(league.leagueName))
                    .environment(storage)
            }
        }
        #else
        NavigationLink {
            CompetitionPage(competitions: sportLeagues)
                .environment(storage)
        } label: {
            HStack {
                Label("Leagues", systemImage: "list.bullet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(hiddenCount > 0 ? "\(sportLeagues.count - hiddenCount) of \(sportLeagues.count)" : "All \(sportLeagues.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
