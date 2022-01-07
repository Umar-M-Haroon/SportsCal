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
                Text(visitingOrAway == .home ? "H" : "A")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel(visitingOrAway == .home ? "Home" : "Away")
                Group {
                    Text(teamName)
                        .bold()
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if let score = score {
                        Text("\(score)")
                    }
                }
                .modifier(WinnerBackground(winner: isWinner))
            }
        } else {
            HStack {
                Text(visitingOrAway == .home ? "H" : "A")
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
                .background(BackgroundView(), alignment: .center)
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

//struct TeamView_Previews: PreviewProvider {
//    static var previews: some View {
//        VStack {
//            TeamView()
//        }
//        .preferredColorScheme(.dark)
//        
//    }
//}
