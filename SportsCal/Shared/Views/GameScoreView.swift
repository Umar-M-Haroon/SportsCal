//
//  GameScoreView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/24/22.
//

import SwiftUI
import SportsCalModel
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

struct GameScoreView: View {
    var homeTeam: Team
    var awayTeam: Team
    var homeScore: Int
    var awayScore: Int
    var game: Game
    @Environment(Favorites.self) private var favorites
    @Environment(GameViewModel.self) private var viewModel
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    
    var isLive: Bool
    #if canImport(ActivityKit) && os(iOS)
    private let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    #endif

    private var topLeaderStat: String? {
        var parts: [String] = []
        if let leader = game.awayLeaders?.first {
            let abbrev = abbreviatedName(leader.playerName)
            parts.append("\(abbrev) \(leader.displayValue)")
        }
        if let leader = game.homeLeaders?.first {
            let abbrev = abbreviatedName(leader.playerName)
            parts.append("\(abbrev) \(leader.displayValue)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func abbreviatedName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        guard parts.count >= 2 else { return name }
        return "\(parts[0].prefix(1)). \(parts.last!)"
    }

    var body: some View {
        @Bindable var bindableFavorites = favorites
        @Bindable var bindableViewModel = viewModel

        NavigationLink {
            GameDetailView(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                .environment(viewModel)
                .environment(favorites)
        } label: {
            VStack(spacing: 6) {
                HStack {
                    if viewModel.appStorage.debugMode, game.idEvent?.hasPrefix(DebugGameFactory.isFakeEventPrefix) == true {
                        Text("DEBUG")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 4))
                    }
                    IndividualTeamView(teamURL: awayTeam.strTeamBadge, shortName: awayTeam.strTeamShort, longName: awayTeam.strTeam, score: awayScore, isWinning: awayScore > homeScore, isAway: true, record: game.awayRecord)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 8) {
                        if let unformatted = game.strProgress {
                            Text(unformatted)
                                .foregroundColor(.secondary)
                        } else {
                            Text(game.strStatus ?? "")
                                .foregroundColor(.secondary)
                        }
                        if let agg = game.aggregateScore {
                            Text(agg)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if let leg = game.legDisplay {
                            Text(leg)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Menu {
#if canImport(ActivityKit) && os(iOS)
                            if isLive && activitiesEnabled  {
                                LiveActivityButton(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                                    .environment(viewModel)
                            }
                            if !isLive {
                                AutoFollowButton(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                                    .environment(viewModel)
                            }
#endif
                            FavoriteMenu(game: game)
                                .environment(favorites)
                            CalendarButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                            NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    IndividualTeamView(teamURL: homeTeam.strTeamBadge, shortName: homeTeam.strTeamShort, longName: homeTeam.strTeam, score: homeScore, isWinning: homeScore > awayScore, isAway: false, record: game.homeRecord)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // Leader stats for live games
                if isLive, let topStat = topLeaderStat {
                    Text(topStat)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
#Preview {
    @Previewable @State var favorites = Favorites()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())
    
    List {
        GameScoreView(homeTeam:
                .init(strTeam: "Colorado Rockies Long Name", strTeamShort: nil, strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 119, awayScore: 89, game:
                .init(strLeague: "\(Leagues.nba.rawValue)", strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "6", strTimestamp: "2022-10-30T00:03:00", isoDate: nil), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
        .environment(favorites)
        .environment(viewModel)
        GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 3, awayScore: 4, game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "4", strTimestamp: "2022-10-30T00:03:00", isoDate: nil), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
            .environment(favorites)
            .environment(viewModel)
        GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 4, awayScore: 3, game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "4", strTimestamp: "2022-10-30T00:03:00", isoDate: nil), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
            .environment(favorites)
            .environment(viewModel)
        GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 4, awayScore: 6, game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "4", strTimestamp: "2022-10-30T00:03:00", isoDate: nil), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
            .environment(favorites)
            .environment(viewModel)
    }
}
