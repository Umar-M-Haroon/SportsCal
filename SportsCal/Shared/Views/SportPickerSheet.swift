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
                            if sport == .nfl {
                                footballLeagues
                                    .padding(.leading, 28)
                            } else if leagues(for: sport).count > 1 {
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

    /// NFL and college switched on separately, with college's picks under it. Stands in
    /// for the generic "Leagues" row: these are real on/off switches, not visibility of
    /// competitions inside one sport. Turning both off turns Football off, which hides
    /// these rows — turning Football back on brings the NFL back.
    @ViewBuilder
    private var footballLeagues: some View {
        // shouldShowNFL/CFB are @ObservationIgnored; recomputeEnabledSports bumps this.
        let _ = storage.preferenceVersion
        Toggle(isOn: Binding(
            get: { storage.shouldShowNFL },
            set: { storage.shouldShowNFL = $0; storage.recomputeEnabledSports() }
        )) {
            Label("NFL", systemImage: "football.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        Toggle(isOn: Binding(
            get: { storage.shouldShowCFB },
            set: { storage.shouldShowCFB = $0; storage.recomputeEnabledSports() }
        )) {
            Label("College Football", systemImage: "building.columns")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if storage.shouldShowCFB {
            collegePicksRow
                .padding(.leading, 28)
        }
    }

    /// Top 25 and conferences, multi-select. Pushed on iOS; inline on the Mac, like the
    /// per-sport league rows.
    @ViewBuilder
    private var collegePicksRow: some View {
        #if os(macOS)
        DisclosureGroup("Show: \(storage.cfbSelection.summary)") {
            CollegeSelectionList()
        }
        #else
        NavigationLink {
            CollegeSelectionList()
                .navigationTitle("College Football")
        } label: {
            HStack {
                Label("Show", systemImage: "trophy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(storage.cfbSelection.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

/// Which college games to show — the AP Top 25 and any set of conferences. With more than
/// one pick, the football section splits into a heading per pick.
struct CollegeSelectionList: View {
    @Environment(UserDefaultStorage.self) private var storage

    private var selection: CollegeFootballSelection {
        // cfbSelection is @ObservationIgnored; setCollegeSelection bumps this.
        _ = storage.preferenceVersion
        return storage.cfbSelection
    }

    private func update(_ change: (inout CollegeFootballSelection) -> Void) {
        var next = storage.cfbSelection
        change(&next)
        storage.setCollegeSelection(next)
    }

    var body: some View {
        List {
            Section {
                Toggle("AP Top 25", isOn: Binding(
                    get: { selection.top25 },
                    set: { value in update { $0.top25 = value } }
                ))
            } footer: {
                Text("Any game with a ranked team, plus the College Football Playoff. Teams you follow always show, whatever you pick here.")
            }

            Section("Conferences") {
                ForEach(CollegeConference.fbs, id: \.self) { conference in
                    Toggle(conference.displayName, isOn: Binding(
                        get: { selection.conferences.contains(conference) },
                        set: { on in
                            update {
                                if on { $0.conferences.insert(conference) } else { $0.conferences.remove(conference) }
                            }
                        }
                    ))
                }
            }
        }
    }
}
