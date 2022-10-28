//
//  GameScoreView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/24/22.
//

import SwiftUI
import SportsCalModel
import CachedAsyncImage
import ActivityKit

struct GameScoreView: View {
    var homeTeam: Team
    var awayTeam: Team
    var homeScore: Int
    var awayScore: Int
    var game: Game
    @EnvironmentObject var favorites: Favorites
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var isLive: Bool
    var body: some View {
        HStack {
            IndividualTeamView(teamURL: awayTeam.strTeamBadge, shortName: awayTeam.strTeamShort, longName: awayTeam.strTeam, score: awayScore, isWinning: awayScore > homeScore, isAway: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                if let formatted = GameFormatter().string(for: game) {
                    Text(formatted)
                        .foregroundColor(.secondary)
                }
                HStack {
                    FavoriteMenu(game: game)
                        .environmentObject(favorites)
                    if #available(iOS 16.1, *) {
                        if isLive && ActivityAuthorizationInfo().areActivitiesEnabled  {
                            LiveActivityButton(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                        }
                    }
                    Menu {
                        CalendarButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                        NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                    } label: {
                        Image(systemName: "bell")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            IndividualTeamView(teamURL: homeTeam.strTeamBadge, shortName: homeTeam.strTeamShort, longName: homeTeam.strTeam, score: homeScore, isWinning: homeScore > awayScore, isAway: false)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
    
    func seeIfWon(teamBadge: String?) -> Color? {
        guard let teamBadge = teamBadge,
              let URL = URL(string: teamBadge + "/preview"),
              let response = URLCache.shared.cachedResponse(for: URLRequest(url: URL)),
              let image = UIImage(data: response.data),
              let averageColor = image.averageColor else {
            return .white
        }
        var currentHue: CGFloat = 0.0
        var currentSaturation: CGFloat = 0.0
        var currentBrigthness: CGFloat = 0.0
        var currentAlpha: CGFloat = 0.0
        
        if averageColor.getHue(&currentHue, saturation: &currentSaturation, brightness: &currentBrigthness, alpha: &currentAlpha){
            print(currentAlpha)
            if currentAlpha < 0.6 {
                currentAlpha = 0.6
            }
            return Color(UIColor(hue: currentHue,
                           saturation: 1,
                           brightness: 1,
                           alpha: currentAlpha))
        }
        return Color(averageColor)
    }
}
struct GameScoreView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            GameScoreView(homeTeam:
                    .init(strTeam: "Colorado Rockies Long Name", strTeamShort: nil, strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 119, awayScore: 89, game:
                    .init(strLeague: "\(Leagues.nba.rawValue)", strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "6", strTimestamp: "2022-10-30T00:03:00"), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
            .environmentObject(Favorites())
            GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 3, awayScore: 4, game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "4", strTimestamp: "2022-10-30T00:03:00"), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
                .environmentObject(Favorites())
            GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 4, awayScore: 3, game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "4", strTimestamp: "2022-10-30T00:03:00"), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
                .environmentObject(Favorites())
            GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 4, awayScore: 6, game: .init(strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "4", strTimestamp: "2022-10-30T00:03:00"), shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
                .environmentObject(Favorites())
        }
    }
}
extension HorizontalAlignment {
    /// A custom alignment for image titles.
    private struct buttonAlignment: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            // Default to bottom alignment if no guides are set.
            context[HorizontalAlignment.center]
        }
    }
    
    /// A guide for aligning titles.
    static let buttonAlignmentGuide = HorizontalAlignment(
        buttonAlignment.self
    )
}
