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

    private struct InfoSnippet: Identifiable, Equatable {
        let id: String
        let icon: String?
        let text: String
    }

    private var infoSnippets: [InfoSnippet] {
        var snippets: [InfoSnippet] = []

        // Last play — biased on live games (duplicated so it lands twice per cycle)
        if let raw = game.lastPlay?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let play = InfoSnippet(id: "lastPlay", icon: "quote.bubble.fill", text: raw)
            snippets.append(play)
            if isLive {
                snippets.append(InfoSnippet(id: "lastPlay.repeat", icon: play.icon, text: play.text))
            }
        }

        // Leaders paired by category (up to 3)
        for pair in leaderPairsByCategory().prefix(3) {
            let away = "\(abbreviatedName(pair.away.playerName)) \(pair.away.displayValue)"
            let home = "\(abbreviatedName(pair.home.playerName)) \(pair.home.displayValue)"
            let text = "\(pair.home.categoryDisplay): \(away) · \(home)"
            snippets.append(InfoSnippet(id: "leader.\(pair.category)", icon: "chart.bar.fill", text: text))
        }

        // Venue
        if let venue = game.venueName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !venue.isEmpty {
            snippets.append(InfoSnippet(id: "venue", icon: "mappin.and.ellipse", text: venue))
        }

        return snippets
    }

    private func leaderPairsByCategory() -> [(category: String, home: GameLeader, away: GameLeader)] {
        guard let home = game.homeLeaders, let away = game.awayLeaders else { return [] }
        var result: [(String, GameLeader, GameLeader)] = []
        for h in home {
            if let a = away.first(where: { $0.category == h.category }) {
                result.append((h.category, h, a))
            }
        }
        return result
    }

    private func abbreviatedName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        guard parts.count >= 2 else { return name }
        return "\(parts[0].prefix(1)). \(parts.last!)"
    }

    @ViewBuilder
    private var rotatingInfoLine: some View {
        let snippets = infoSnippets
        if !snippets.isEmpty {
            TimelineView(.periodic(from: .now, by: 4.0)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate / 4.0)
                let snippet = snippets[((tick % snippets.count) + snippets.count) % snippets.count]
                HStack(spacing: 4) {
                    if let icon = snippet.icon {
                        Image(systemName: icon)
                            .font(.caption2)
                    }
                    Text(snippet.text)
                        .font(.caption2)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.35), value: snippet.id)
            }
        }
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
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            if isLive {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 6, height: 6)
                            }
                            if let statusText = game.displayStatus {
                                Text(statusText)
                                    .foregroundColor(isLive ? .red : .secondary)
                            }
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
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    IndividualTeamView(teamURL: homeTeam.strTeamBadge, shortName: homeTeam.strTeamShort, longName: homeTeam.strTeam, score: homeScore, isWinning: homeScore > awayScore, isAway: false, record: game.homeRecord, seed: game.homeSeed)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // Rotating info: last play (weighted on live), leader categories, venue
                rotatingInfoLine

                if game.playoff != nil {
                    PlayoffPill(
                        game: game,
                        homeTeamShort: homeTeam.strTeamShort,
                        awayTeamShort: awayTeam.strTeamShort
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .contextMenu {
#if canImport(ActivityKit) && os(iOS)
                if isLive && activitiesEnabled {
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
            }

        if navigationDisabled {
            content
        } else {
            NavigationLink {
                AdaptiveGameDetail(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
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
