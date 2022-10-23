//
//  TeamView.swift
//  SportsCal
//
//  Created by Umar Haroon on 12/15/21.
//

import Foundation
import SwiftUI
enum HomeOrAway {
    case home
    case away
}
struct TeamView: View {
    var teamName: String
    var visitingOrAway: HomeOrAway
    var game: Game
    var isPast: Bool {
        game.homeScore != nil && game.awayScore != nil
    }
    var score: Int?
    var isWinner: Bool {
        if isPast {
            switch visitingOrAway {
            case .home:
                guard let awayScore = game.awayScore,
                      let homeScore = game.homeScore else { return false }
                return homeScore > awayScore
            case .away:
                guard let awayScore = game.awayScore,
                      let homeScore = game.homeScore else { return false }
                return awayScore > homeScore
            }
        }
        return false
    }
    var body: some View {
        
        if isPast {
            HStack {
                Image(systemName: visitingOrAway == .home ? "house.fill" : "airplane")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel(visitingOrAway == .home ? "Home" : "Away")
                Group {
                    Text(teamName)
                        .font(.system(.body, design: .rounded))
//                        .fontWeight(.semibold)
                        .modifier(WinnerBackground(winner: isWinner))
                        .multilineTextAlignment(.leading)
                    if let score = score {
                        Spacer()
                        Text("\(score)")
                    }
                }
            }
        } else {
            HStack {
                Image(systemName: visitingOrAway == .home ? "house.fill" : "airplane")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel(visitingOrAway == .home ? "Home" : "Away")
                Text(teamName)
                    .bold()
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

struct WinnerBackground: ViewModifier {
    var winner: Bool?
    func body(content: Content) -> some View {
        if winner ?? false {
            content
//                .fontWeight(.semibold)
        } else {
            content
        }
    }
}
struct BackgroundView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .foregroundColor(.secondary)
            .opacity(0.6)
            .padding(-2)
    }
}

struct TeamView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TeamView(teamName: "Boston Celtics", visitingOrAway: .away, game: Game(nbaGame: .init(id: "test", status: "test", title: "Test Game", coverage: "ESPN", scheduled: "IDK", home_points: 82, away_points: 80, track_on_court: true, sr_id: "test", reference: "test", time_zones: .init(venue: "Barclays", home: "Warriors", away: "Bucks"), venue: nil, broadcasts: nil, home: .init(name: "Warriors", alias: "GSW", id: "GSW", sr_id: "Test", reference: "test"), away: .init(name: "Bucks", alias: "MIL", id: "Bucks", sr_id: "Bucks", reference: "bucks"))))
        }
        .preferredColorScheme(.dark)
        
    }
}
