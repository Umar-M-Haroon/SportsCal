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
    @Environment(Favorites.self) private var favorites: Favorites?
    @Environment(\.dismiss) private var dismiss

    @State private var sports: [SportType] = []

    var body: some View {
        NavigationStack {
            Group {
            #if os(macOS)
            macForm
            #else
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
                                Label("Only my teams", systemImage: "star.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 28)
                            if showsEmptyNote(for: sport) {
                                EmptyFavoritesNote(text: FavoriteReach.emptyNote(sport.displayName))
                                    .padding(.leading, 28)
                            }
                            if EventCoverage.sports.contains(sport) {
                                coveragePicker(for: sport)
                                    .padding(.leading, 28)
                            }
                            if sport == .nfl {
                                footballLeagues
                                    .padding(.leading, 28)
                            } else if sport == .basketball {
                                basketballLeagues
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
            #endif
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
        .frame(minWidth: 460, idealWidth: 500, minHeight: 560, idealHeight: 680)
        #endif
    }

    /// True when the sport shows only the user's teams and none of them has a game in it.
    private func showsEmptyNote(for sport: SportType) -> Bool {
        _ = storage.preferenceVersion
        guard storage.favoritesOnly(for: sport), let favorites else { return false }
        return !FavoriteReach.hasGames(in: sport, viewModel: viewModel, favorites: favorites)
    }

    // MARK: - Mac

    #if os(macOS)
    /// A grouped form, one section per sport: the sport's switch heads it, and what it
    /// shows sits underneath as plain labelled rows (no per-row icons, which on the Mac
    /// read as decoration rather than meaning).
    private var macForm: some View {
        Form {
            ForEach(sports, id: \.self) { sport in
                Section {
                    macSportHeader(sport)
                    if storage.effectiveShouldShow(sport) {
                        macShowPicker(sport)
                        if EventCoverage.sports.contains(sport) {
                            macCoveragePicker(sport)
                        }
                        if sport == .nfl {
                            macFootballLeagues
                        } else if sport == .basketball {
                            BasketballLeagueToggles(macStyle: true)
                        } else if leagues(for: sport).count > 1 {
                            macLeaguesLink(sport)
                        }
                    }
                } footer: {
                    if sport == sports.last {
                        Text("Right-click a sport to move it up or down, or drag columns on the board.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationDestination(for: SportType.self) { sport in
            Form {
                Section {
                    ForEach(leagues(for: sport), id: \.self) { league in
                        CompetitionView(league: league, isShown: !storage.hiddenCompetitions.contains(league.leagueName))
                    }
                } footer: {
                    if storage.favoritesOnly(for: sport) {
                        Text("\(sport.displayName) is set to only your teams, which applies to every league here.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("\(sport.displayName) Leagues")
        }
    }

    private func macSportHeader(_ sport: SportType) -> some View {
        Toggle(isOn: Binding(
            get: { storage.effectiveShouldShow(sport) },
            set: { storage.toggleSport(sport, enabled: $0) }
        )) {
            HStack(spacing: 10) {
                Image(systemName: sport.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.app(sport).gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(sport.displayName)
                    .font(.headline)
            }
        }
        .toggleStyle(.switch)
        .contextMenu {
            Button("Move Up") { move(sport, by: -1) }
                .disabled(sports.first == sport)
            Button("Move Down") { move(sport, by: 1) }
                .disabled(sports.last == sport)
        }
    }

    /// Reorders from the sport's context menu (the form can't drag sections).
    private func move(_ sport: SportType, by offset: Int) {
        guard let from = sports.firstIndex(of: sport) else { return }
        let to = from + offset
        guard sports.indices.contains(to) else { return }
        withAnimation { sports.swapAt(from, to) }
        storage.sportOrder = sports.map(\.rawValue)
        storage.recomputeEnabledSports()
    }

    /// Every game, or only the user's teams' games. Replaces the star "Favorites only"
    /// checkbox.
    @ViewBuilder
    private func macShowPicker(_ sport: SportType) -> some View {
        let _ = storage.preferenceVersion
        Picker("Games", selection: Binding(
            get: { storage.favoritesOnly(for: sport) },
            set: { storage.setFavoritesOnly(sport, value: $0); storage.bumpPreferenceVersion() }
        )) {
            Text("All games").tag(false)
            Text("Only my teams").tag(true)
        }
        .pickerStyle(.menu)
        if showsEmptyNote(for: sport) {
            EmptyFavoritesNote(text: FavoriteReach.emptyNote(sport.displayName))
        }
    }

    private func macCoveragePicker(_ sport: SportType) -> some View {
        _ = storage.preferenceVersion
        let selection = Binding(
            get: { storage.coverage(for: sport) },
            set: { storage.setCoverage($0, for: sport) }
        )
        return Picker(selection: selection) {
            ForEach(EventCoverage.allCases, id: \.self) { coverage in
                Text(coverage.displayName(for: sport)).tag(coverage)
            }
        } label: {
            Text("Events")
            Text(selection.wrappedValue.summary(for: sport))
        }
        .pickerStyle(.menu)
    }

    private func macLeaguesLink(_ sport: SportType) -> some View {
        let sportLeagues = leagues(for: sport)
        let hidden = sportLeagues.filter { storage.hiddenCompetitions.contains($0.leagueName) }.count
        return NavigationLink(value: sport) {
            LabeledContent("Leagues") {
                Text(hidden > 0 ? "\(sportLeagues.count - hidden) of \(sportLeagues.count) shown" : "All \(sportLeagues.count) shown")
            }
        }
    }

    @ViewBuilder
    private var macFootballLeagues: some View {
        let _ = storage.preferenceVersion
        Toggle("NFL", isOn: Binding(
            get: { storage.shouldShowNFL },
            set: { storage.shouldShowNFL = $0; storage.recomputeEnabledSports() }
        ))
        .toggleStyle(.switch)
        Toggle("College Football", isOn: Binding(
            get: { storage.shouldShowCFB },
            set: { storage.shouldShowCFB = $0; storage.recomputeEnabledSports() }
        ))
        .toggleStyle(.switch)
        if storage.shouldShowCFB {
            NavigationLink {
                Form { CollegeSelectionList() }
                    .formStyle(.grouped)
                    .navigationTitle("College Football")
            } label: {
                LabeledContent("College games") {
                    Text(storage.cfbSelection.summary)
                }
            }
        }
    }
    #endif

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

    @ViewBuilder
    private var basketballLeagues: some View {
        BasketballLeagueToggles()
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

/// NBA, WNBA and college basketball switched on separately, as football is. They stand in
/// for the generic "Leagues" row: the WNBA and college have their own switches, which a
/// hidden-competition row couldn't turn on. Switching a league on also un-hides it, so an
/// old hidden-competition choice can't leave the switch inert.
struct BasketballLeagueToggles: View {
    @Environment(UserDefaultStorage.self) private var storage
    /// Plain switches with no icons, for the Mac's grouped form.
    var macStyle = false

    var body: some View {
        // The switches are @ObservationIgnored; recomputeEnabledSports bumps this.
        let _ = storage.preferenceVersion
        leagueSwitch("NBA", systemImage: "basketball.fill", league: .nba, isOn: \.shouldShowNBA)
        leagueSwitch("WNBA", systemImage: "basketball.fill", league: .wnba, isOn: \.shouldShowWNBA)
        leagueSwitch("College Basketball", systemImage: "building.columns", league: .ncaaMBBTournament, isOn: \.shouldShowCBB)
    }

    private func leagueSwitch(_ title: String, systemImage: String, league: Leagues,
                              isOn keyPath: ReferenceWritableKeyPath<UserDefaultStorage, Bool>) -> some View {
        let isOn = Binding(
            get: { storage[keyPath: keyPath] && !storage.hiddenCompetitions.contains(league.leagueName) },
            set: { on in
                storage[keyPath: keyPath] = on
                if on { storage.hiddenCompetitions.removeAll { $0 == league.leagueName } }
                storage.recomputeEnabledSports()
            }
        )
        return Group {
            if macStyle {
                Toggle(title, isOn: isOn)
                    .toggleStyle(.switch)
            } else {
                Toggle(isOn: isOn) {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}


#Preview("Sports sheet") {
    @Previewable @State var storage = UserDefaultStorage()
    @Previewable @State var favorites = Favorites()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())
    SportPickerSheet()
        .environment(storage)
        .environment(viewModel)
        .environment(favorites)
        .onAppear { storage.setFavoritesOnly(.soccer, value: true); storage.setFavoritesOnly(.tennis, value: true) }
        .frame(height: 2200)
}
