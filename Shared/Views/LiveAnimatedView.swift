//
//  LiveAnimatedView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/25/22.
//

import SwiftUI
import SportsCalModel

struct LiveAnimatedView: View {
    @State var animationScale: Double = 1
    var repeatingAnimation: Animation {
        Animation
            .easeInOut(duration: 0.6)
            .delay(0.15)
            .repeatForever()
    }
    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationScale)
                    .foregroundColor(.red)
                    .opacity(0.5)
                    .transition(.scale(scale: 2.5))
                    .onAppear {
                        withAnimation(repeatingAnimation) {
                            self.animationScale = 2.5
                        }
                    }
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundColor(.red)
            }
            .padding(2)
            Text("Live".uppercased())
                .font(.headline)
                .foregroundColor(.red)
        }
    }
}

//struct LiveAnimatedView_Previews: PreviewProvider {
//    static var previews: some View {
//        List {
//            Section {
//                GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 4, awayScore: 12)
//            } header: {
//                LiveAnimatedView()
//            }
//
//        }
//    }
//}
