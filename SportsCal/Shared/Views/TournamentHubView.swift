//
//  TournamentHubView.swift
//  SportsCal (iOS)
//
//  Day-by-day view of a single tennis tournament (e.g. Roland Garros). A pinned day strip
//  lets you jump between match days; within a day matches are grouped by round. Replaces the
//  "endless flat list" of tennis matches with a drill-in structure.
//

import SwiftUI
import SportsCalModel

struct TournamentHubView: View {
    let tournamentName: String
    let games: [Game]
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?

    @State private var selectedDay: Date?
    @State private var selectedTour: Leagues?

    // MARK: Derived

    /// Tours present in this tournament, in ATP → WTA order. Combined events (Grand Slams,
    /// Indian Wells…) have both; single-tour events have one.
    private var toursPresent: [Leagues] {
        let set = Set(games.compactMap { game -> Leagues? in
            guard let lg = game.idLeague, let i = Int(lg) else { return nil }
            return Leagues(rawValue: i)
        })
        return [Leagues.atp, .wta].filter { set.contains($0) }
    }

    /// Games for the selected tour (Men's = ATP, Women's = WTA). Falls back to all games when the
    /// tournament is single-tour or no tour is selected yet.
    private var activeGames: [Game] {
        guard toursPresent.count > 1, let tour = selectedTour else { return games }
        return games.filter { $0.idLeague == "\(tour.rawValue)" }
    }

    /// Binding for the tour picker — defaults to the first tour present and clears the selected day
    /// so the day strip re-resolves against the newly selected draw.
    private var tourBinding: Binding<Leagues> {
        Binding(
            get: { selectedTour ?? toursPresent.first ?? .atp },
            set: { selectedTour = $0; selectedDay = nil }
        )
    }

    /// Unique match days (start-of-day), ascending.
    private var days: [Date] {
        let cal = Calendar.current
        let set = Set(activeGames.compactMap { $0.standardDate.map { cal.startOfDay(for: $0) } })
        return set.sorted()
    }

    private var resolvedDay: Date? {
        selectedDay ?? defaultDay
    }

    /// Default to today if the tournament is on today, else the first day with a live match,
    /// else the next upcoming day, else the last day.
    private var defaultDay: Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if days.contains(today) { return today }
        if let live = activeGames.first(where: { $0.strStatus?.lowercased() == "in" })?.standardDate {
            return cal.startOfDay(for: live)
        }
        if let nextUp = days.first(where: { $0 >= today }) { return nextUp }
        return days.last
    }

    private func matches(on day: Date) -> [Game] {
        let cal = Calendar.current
        return activeGames
            .filter { $0.standardDate.map { cal.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { ($0.standardDate ?? .distantPast) < ($1.standardDate ?? .distantPast) }
    }

    /// Matches for the selected day grouped by round, preserving first-appearance order.
    private func roundGroups(_ matches: [Game]) -> [(round: String, matches: [Game])] {
        var result: [(round: String, matches: [Game])] = []
        var seen: [String: Int] = [:]
        for game in matches {
            let key = game.round ?? "Matches"
            if let idx = seen[key] {
                result[idx].matches.append(game)
            } else {
                seen[key] = result.count
                result.append((round: key, matches: [game]))
            }
        }
        return result
    }

    // MARK: Body

    var body: some View {
        List {
            if toursPresent.count > 1 {
                Section {
                    Picker("Tour", selection: tourBinding) {
                        Text("Men's").tag(Leagues.atp)
                        Text("Women's").tag(Leagues.wta)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            if days.count > 1 {
                Section {
                    dayStrip
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }

            if let day = resolvedDay {
                let dayMatches = matches(on: day)
                if dayMatches.isEmpty {
                    Section { Text("No matches scheduled").foregroundStyle(.secondary) }
                } else {
                    ForEach(roundGroups(dayMatches), id: \.round) { group in
                        Section {
                            ForEach(group.matches, id: \.id) { game in
                                matchRow(game)
                            }
                        } header: {
                            Text(group.round)
                        }
                    }
                }
            } else {
                Section { Text("No matches available").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(tournamentName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Day strip

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        dayPill(day)
                            .id(day)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear {
                if let day = resolvedDay {
                    proxy.scrollTo(day, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func dayPill(_ day: Date) -> some View {
        let isSelected = resolvedDay.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
        let hasLive = matches(on: day).contains { $0.strStatus?.lowercased() == "in" }
        Button {
            selectedDay = day
        } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2)
                Text(day.formatted(.dateTime.day()))
                    .font(.headline)
                if hasLive {
                    Circle().fill(.red).frame(width: 5, height: 5)
                } else {
                    Circle().fill(.clear).frame(width: 5, height: 5)
                }
            }
            .frame(width: 44)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.app(.tennis).opacity(0.2) : Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.app(.tennis) : .clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Match row

    @ViewBuilder
    private func matchRow(_ game: Game) -> some View {
        let isLive = game.strStatus?.lowercased() == "in"
        NavigationLink {
            TennisMatchDetailView(game: game)
                .environment(viewModel)
                .environment(favorites)
        } label: {
            TennisMatchScoreView(
                game: game,
                shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                sheetType: $sheetType,
                isLive: isLive
            )
            .environment(viewModel)
            .environment(favorites)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var favorites = Favorites()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())

    func match(_ home: String, _ away: String, _ ts: String, round: String, status: String = "post",
               tour: Leagues = .atp, h: [Double]? = nil, a: [Double]? = nil) -> Game {
        Game(idLeague: "\(tour.rawValue)", strHomeTeam: home, strAwayTeam: away,
             strStatus: status, strTimestamp: ts,
             homeLinescores: h, awayLinescores: a, isoDate: nil,
             tournamentName: "Roland Garros", round: round)
    }

    // Combined event — both tours present, so the Men's/Women's segment shows.
    let games: [Game] = [
        match("Carlos Alcaraz", "Jannik Sinner", "2026-06-07T13:00:00Z", round: "Final", status: "in", tour: .atp, h: [6,4,6], a: [3,6,2]),
        match("Novak Djokovic", "Alexander Zverev", "2026-06-05T11:00:00Z", round: "Semifinal", tour: .atp, h: [7,6,6], a: [5,4,3]),
        match("Iga Swiatek", "Coco Gauff", "2026-06-05T13:30:00Z", round: "Semifinal", tour: .wta, h: [6,6], a: [4,3]),
        match("Aryna Sabalenka", "Jessica Pegula", "2026-06-04T10:00:00Z", round: "Quarterfinal", tour: .wta, h: [6,7], a: [4,5]),
    ]

    return NavigationStack {
        TournamentHubView(tournamentName: "Roland Garros", games: games,
                          shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil))
            .environment(viewModel)
            .environment(favorites)
    }
}
