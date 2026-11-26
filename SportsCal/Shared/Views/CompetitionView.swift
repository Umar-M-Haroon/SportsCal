//
//  CompetitionView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/4/22.
//

import SwiftUI
import NukeUI
import SportsCalModel
import WidgetKit

/// How much of a sport or league the user sees. One choice in place of the old pair of
/// switches ("shown" plus a star "Favorites only"), whose meaning wasn't clear.
enum ScheduleShowMode: Hashable, CaseIterable {
    case hidden, allGames, myTeams

    var title: String {
        switch self {
        case .hidden: "Hidden"
        case .allGames: "All games"
        case .myTeams: "Only my teams"
        }
    }
}

/// Whether any of the user's teams (or players) has a game in the loaded schedule, so a
/// "only my teams" choice that would leave a sport or league empty can say so.
enum FavoriteReach {
    @MainActor
    static func hasGames(in sport: SportType, league: Leagues? = nil,
                         viewModel: GameViewModel, favorites: Favorites) -> Bool {
        let matcher = favorites.matcher
        let leagueID = league.map { String($0.rawValue) }
        return (viewModel.gamesDict[sport] ?? []).contains { game in
            (leagueID == nil || game.idLeague == leagueID) && matcher.matches(game)
        }
    }

    /// The note under a sport or league set to "only my teams" that none of the user's
    /// teams play in.
    static func emptyNote(_ name: String) -> String {
        "None of your teams have \(name) games coming up, so it will stay empty."
    }
}

/// The warning shown when "only my teams" leaves something empty.
struct EmptyFavoritesNote: View {
    var text: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// One competition's visibility: hidden, every game, or only the user's teams.
struct CompetitionView: View {
    var league: Leagues
    @State var isShown: Bool = true
    @State private var mode: ScheduleShowMode = .allGames
    @Environment(UserDefaultStorage.self) private var appStorage
    @Environment(GameViewModel.self) private var viewModel: GameViewModel?
    @Environment(Favorites.self) private var favorites: Favorites?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                logo
                Text(league.leagueName)
                    .foregroundStyle(mode == .hidden ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Picker(league.leagueName, selection: $mode) {
                    ForEach(ScheduleShowMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            if showsEmptyNote {
                EmptyFavoritesNote(text: FavoriteReach.emptyNote(league.leagueName))
                    .padding(.leading, 34)
            }
        }
        .onChange(of: mode) { _, newValue in apply(newValue) }
        .onAppear {
            mode = !isShown || appStorage.hiddenCompetitions.contains(league.leagueName)
                ? .hidden
                : (appStorage.isFavoritesOnly(competition: league.leagueName) ? .myTeams : .allGames)
        }
    }

    private var logo: some View {
        let logoURL = colorScheme == .dark ? league.darkLogoURL : league.logoURL
        return Group {
            if let logoURL {
                LazyImage(request: ImageRequest(url: logoURL, processors: [.resize(size: CGSize(width: 24, height: 24))])) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        placeholderLogo
                    }
                }
            } else {
                placeholderLogo
            }
        }
        .frame(width: 24, height: 24)
        .opacity(mode == .hidden ? 0.45 : 1)
    }

    private var placeholderLogo: some View {
        Image(systemName: SportType(league: league).systemImage)
            .foregroundStyle(.secondary)
    }

    private var showsEmptyNote: Bool {
        guard mode == .myTeams, let viewModel, let favorites else { return false }
        return !FavoriteReach.hasGames(in: SportType(league: league), league: league,
                                       viewModel: viewModel, favorites: favorites)
    }

    private func apply(_ mode: ScheduleShowMode) {
        let name = league.leagueName
        if mode == .hidden {
            if !appStorage.hiddenCompetitions.contains(name) {
                appStorage.hiddenCompetitions.append(name)
            }
        } else {
            appStorage.hiddenCompetitions.removeAll { $0 == name }
            appStorage.setFavoritesOnly(competition: name, value: mode == .myTeams)
        }
        isShown = mode != .hidden
        appStorage.syncHiddenCompetitions()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#Preview {
    @Previewable @State var storage = UserDefaultStorage()
    @Previewable @State var favorites = Favorites()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())
    Form {
        Section {
            ForEach([Leagues.English_Premier_League, .La_Liga, .Serie_A, .Ligue_1], id: \.self) { league in
                CompetitionView(league: league)
            }
        }
    }
    .formStyle(.grouped)
    .environment(storage)
    .environment(favorites)
    .environment(viewModel)
    .onAppear {
        storage.hiddenCompetitions.removeAll { $0 == Leagues.Ligue_1.leagueName }
        storage.setFavoritesOnly(competition: Leagues.Serie_A.leagueName, value: true)
    }
}
