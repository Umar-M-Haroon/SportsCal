//
//  UpcomingGameView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/26/22.
//
import SwiftUI
import SportsCalModel
import CachedAsyncImage

struct UpcomingGameView: View {
    var homeTeam: Team 
    var awayTeam: Team
    var game: Game!
    @Binding var showCountdown: Bool
    @State var timeRemaining: TimeInterval = 0
    @State var timeString: String = ""
    var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State var accessibilityLabel: String = "days: hours"
    @EnvironmentObject var favorites: Favorites
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var body: some View {
        HStack {
            IndividualTeamView(teamURL: awayTeam.strTeamBadge, shortName: awayTeam.strTeamShort, longName: awayTeam.strTeam, score: Int(game.intAwayScore ?? ""), isWinning: (Int(game.intAwayScore ?? "") ?? 0) > (Int(game.intHomeScore ?? "") ?? 0), isAway: true)
            .frame(maxWidth: .infinity)
            VStack(alignment: .center, spacing: 8) {
                if showCountdown {
                    Text(timeString)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.medium)
                        .accessibilityValue(accessibilityLabel)
                        .accessibilityLabel(accessibilityLabel)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .onReceive(timer) { cur in
                            withAnimation {
                                timeString = formatCountdown()
                            }
                        }
                }
                if let isoString = game?.strTimestamp,
                    let isoDate = format(isoString) {
                    Text(isoDate)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                HStack {
                    FavoriteMenu(game: game)
                        .environmentObject(favorites)
                    Menu {
                        CalendarButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                        NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                    } label: {
                        Image(systemName: "clock")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            IndividualTeamView(teamURL: homeTeam.strTeamBadge, shortName: homeTeam.strTeamShort, longName: homeTeam.strTeam, score: Int(game.intHomeScore ?? ""), isWinning: (Int(game.intHomeScore ?? "") ?? 0) > (Int(game.intAwayScore ?? "") ?? 0), isAway: false)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            timeString = formatCountdown()
        }
    }
    
    func formatCountdown() -> String {
        guard let gameDateString = game.strTimestamp,
              let gameDate = DateFormatters.isoFormatter.date(from: gameDateString) else { return "" }
        timeRemaining = gameDate.timeIntervalSince(Date())
        if timeRemaining < 0 {
            return DateFormatters.relativeFormatter.localizedString(for: gameDate, relativeTo: Date())
        }
        let components = Calendar.current.dateComponents([.day, .hour, .minute, .second], from: .now, to: gameDate)
        var finalString = ""
        if components.day ?? -1 > 1 {
            finalString = String(format:"%2i days: %02i:%02i:%02i", components.day!, components.hour!, components.minute!, components.second!)
            accessibilityLabel = String(format:"%2i days, %2i hours, %2i minutes, %2i seconds", components.day!, components.hour!, components.minute!, components.second!)
        } else if components.day ?? -1 == 1 {
            finalString = String(format:"%2i day: %02i:%02i:%02i", components.day!, components.hour!, components.minute!, components.second!)
            accessibilityLabel = String(format:"%2i day, %2i hours, %2i minutes, %2i seconds", components.day!, components.hour!, components.minute!, components.second!)
        } else {
            finalString = String(format: "%2i:%02i:%02i", components.hour!, components.minute!, components.second!)
            accessibilityLabel = String(format:"%2i hours, %2i minutes, %2i seconds", components.day!, components.hour!, components.minute!, components.second!)
        }
        return finalString
    }
    
    func format(_ date: String?) -> String {
        guard let dateString = date,
              let date = DateFormatters.isoFormatter.date(from: dateString) else { return "" }
        DateFormatters.dateFormatter.dateStyle = .none
        DateFormatters.dateFormatter.timeStyle = .short
        return DateFormatters.dateFormatter.string(from: date)
    }
}

struct UpcomingGameView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            GameScoreView(homeTeam:
                    .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 119, awayScore: 89, game:
                    .init(strLeague: "\(Leagues.nba.rawValue)", strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "6", strTimestamp: "2022-10-30T00:03:00"), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
                .environmentObject(Favorites())
            GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 12, awayScore: 4, game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strTimestamp: "2022-10-30T00:03:00"), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
                .environmentObject(Favorites())
            GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 4, awayScore: 3, game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strTimestamp: "2022-10-30T00:03:00"), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
                .environmentObject(Favorites())
            GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 4, awayScore: 6, game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strTimestamp: "2022-10-30T00:03:00"), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
                .environmentObject(Favorites())
        }
    }
}
