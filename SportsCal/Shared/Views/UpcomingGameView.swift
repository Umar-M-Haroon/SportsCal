//
//  UpcomingGameView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/26/22.
//
import SwiftUI
import SportsCalModel

struct UpcomingGameView: View {
    var homeTeam: Team 
    var awayTeam: Team
    var game: Game!
    @Binding var showCountdown: Bool
    @State var timeRemaining: TimeInterval = 0
    var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State var accessibilityLabel: String = "days: hours"
    @Environment(Favorites.self) private var favorites
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    @State var dateFormat: Int
    @Environment(GameViewModel.self) private var viewModel
    var isFavorite: Bool = false
    var navigationDisabled: Bool = false
    var formatter =  Date.RelativeFormatStyle(presentation: .numeric, capitalizationContext: .beginningOfSentence)

    private var isStartingSoon: Bool {
        guard let date = game.standardDate else { return false }
        let interval = date.timeIntervalSinceNow
        return interval > 0 && interval <= 1800 // within 30 minutes
    }

    private var timeColor: Color {
        isStartingSoon ? .orange : .secondary
    }

    var body: some View {
        let content = VStack(spacing: 6) {
                HStack {
                    IndividualTeamView(teamURL: awayTeam.strTeamBadge, shortName: awayTeam.strTeamShort, longName: awayTeam.strTeam, score: Int(game.intAwayScore ?? ""), isWinning: false, isAway: true, record: game.awayRecord, seed: game.awaySeed)
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .center, spacing: 8) {
                        if showCountdown, let date = game.standardDate {
                            Text(formatter.format(date))
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.medium)
                                .accessibilityValue(accessibilityLabel)
                                .accessibilityLabel(accessibilityLabel)
                                .foregroundColor(timeColor)
                        } else if isFavorite, let isoDate = game.standardDate {
                            Text(isoDate.formatted(.dateTime.hour().minute()))
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.medium)
                                .accessibilityValue(accessibilityLabel)
                                .accessibilityLabel(accessibilityLabel)
                                .foregroundColor(timeColor)

                        }
                        if let isoDateString = game.standardDate?.formatToTime() {
                            Text(isoDateString)
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundColor(timeColor)
                        }
                        Menu {
                            #if canImport(ActivityKit) && os(iOS)
                            AutoFollowButton(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                                .environment(viewModel)
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
                        .fixedSize(horizontal: true, vertical: false)
                    IndividualTeamView(teamURL: homeTeam.strTeamBadge, shortName: homeTeam.strTeamShort, longName: homeTeam.strTeam, score: Int(game.intHomeScore ?? ""), isWinning: false, isAway: false, record: game.homeRecord, seed: game.homeSeed)
                    .frame(maxWidth: .infinity)
                }

                // Venue for favorites
                if isFavorite, let venue = game.venueName {
                    Text(venue)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
    @Previewable @State var storage = UserDefaultStorage()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())
    
    List {
        GameScoreView(homeTeam:
                .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 119, awayScore: 89, game:
                .init(strLeague: "\(Leagues.nba.rawValue)", strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "Bottom 6th", strTimestamp: "2022-10-30T00:03:00", isoDate: nil), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
            .environment(favorites)
            .environment(viewModel)
        GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 12, awayScore: 4, game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strTimestamp: "2022-10-30T00:03:00", isoDate: nil), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
            .environment(favorites)
            .environment(viewModel)
        GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 4, awayScore: 3, game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strTimestamp: "2022-10-30T00:03:00", isoDate: nil), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
            .environment(favorites)
            .environment(viewModel)
        GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 4, awayScore: 6, game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strTimestamp: "2022-10-30T00:03:00", isoDate: nil), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
            .environment(favorites)
            .environment(viewModel)
        UpcomingGameView(homeTeam: Team(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strTimestamp: "2022-11-21T11:11:00+00:00", isoDate: nil), showCountdown: .constant(true), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(.none), dateFormat: 2, isFavorite: false)
            .environment(favorites)
            .environment(viewModel)
        UpcomingGameView(homeTeam: Team(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strTimestamp: "2023-03-28T11:12:10+00:00", isoDate: nil), showCountdown: .constant(true), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(.none), dateFormat: 2, isFavorite: false)
            .environment(favorites)
            .environment(viewModel)
    }
}
