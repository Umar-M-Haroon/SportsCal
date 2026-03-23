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
    var navigationDisabled: Bool = false
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

        let content = VStack(spacing: 6) {
                HStack {
                    if viewModel.appStorage.debugMode, game.idEvent?.hasPrefix(DebugGameFactory.isFakeEventPrefix) == true {
                        Text("DEBUG")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 4))
                    }
                    IndividualTeamView(teamURL: awayTeam.strTeamBadge, shortName: awayTeam.strTeamShort, longName: awayTeam.strTeam, score: awayScore, isWinning: awayScore > homeScore, isAway: true, record: game.awayRecord, seed: game.awaySeed)
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
                    IndividualTeamView(teamURL: homeTeam.strTeamBadge, shortName: homeTeam.strTeamShort, longName: homeTeam.strTeam, score: homeScore, isWinning: homeScore > awayScore, isAway: false, record: game.homeRecord, seed: game.homeSeed)
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

        if navigationDisabled {
            content
        } else {
            NavigationLink {
                GameDetailView(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                    .environment(viewModel)
                    .environment(favorites)
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }
}
#Preview {
    @Previewable @State var favorites = Favorites()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())

    let nbaGame: Game = .init(strLeague: "\(Leagues.nba.rawValue)", strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "6", strTimestamp: "2022-10-30T00:03:00", isoDate: nil, homeTeamColor: "552583", awayTeamColor: "CE1141")
    let mlbGame: Game = .init(strLeague: "\(Leagues.mlb.rawValue)", strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "4", strTimestamp: "2022-10-30T00:03:00", isoDate: nil, homeTeamColor: "333366", awayTeamColor: "003831")
    let nflGame: Game = .init(strLeague: "\(Leagues.nfl.rawValue)", strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "4", strTimestamp: "2022-10-30T00:03:00", isoDate: nil, homeTeamColor: "003594", awayTeamColor: "A71930")
    let soccerGame: Game = .init(strLeague: "\(Leagues.English_Premier_League.rawValue)", strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "4", strTimestamp: "2022-10-30T00:03:00", isoDate: nil, homeTeamColor: "DA291C", awayTeamColor: "6CABDD")

    List {
        GameScoreView(homeTeam:
                .init(strTeam: "Los Angeles Lakers", strTeamShort: "LAL", strAlternate: "LAL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Rockets", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 119, awayScore: 89, game: nbaGame, shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
        .gameCard(game: nbaGame, isLive: true)
        .environment(favorites)
        .environment(viewModel)
        GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 3, awayScore: 4, game: mlbGame, shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: false)
            .gameCard(game: mlbGame, isLive: false)
            .environment(favorites)
            .environment(viewModel)
        GameScoreView(homeTeam: .init(strTeam: "Dallas Cowboys", strTeamShort: "DAL", strAlternate: "DAL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "San Francisco 49ers", strTeamShort: "SF", strAlternate: "SF", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 24, awayScore: 31, game: nflGame, shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
            .gameCard(game: nflGame, isLive: true)
            .environment(favorites)
            .environment(viewModel)
        GameScoreView(homeTeam: .init(strTeam: "Manchester United", strTeamShort: "MUN", strAlternate: "MUN", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Manchester City", strTeamShort: "MCI", strAlternate: "MCI", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 2, awayScore: 1, game: soccerGame, shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: false)
            .gameCard(game: soccerGame, isLive: false)
            .environment(favorites)
            .environment(viewModel)
    }
}
