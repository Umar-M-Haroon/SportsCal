//
//  DecorationView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/19/23.
//

import SwiftUI

@available(iOS 16.0, *)
struct DecorationView: View {
    var showBasketball: Bool
    var showSoccer: Bool
    var showHockey: Bool
    var showBaseball: Bool
    var showFootball: Bool
    var totalShowing: Int {
        var total = 0
        if showBasketball {
            total += 1
        }
        if showSoccer {
            total += 1
        }
        if showHockey {
            total += 1
        }
        if showBaseball {
            total += 1
        }
        if showFootball {
            total += 1
        }
        return total
    }

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 2, verticalSpacing: 0) {
            GridRow {
                if showBasketball {
                    Image(systemName: "basketball.fill")
                        .resizable()
                        .frame(width: 9, height: 9)
                        .modifier(SportsTint(sport: .basketball))
                }
                if showSoccer {
                    Image(systemName: "soccerball")
                        .resizable()
                        .frame(width: 9, height: 9)
                        .modifier(SportsTint(sport: .soccer))
                }
                if showHockey {
                    Image(systemName: "hockey.puck.fill")
                        .resizable()
                        .frame(width: 9, height: 9)
                        .modifier(SportsTint(sport: .hockey))
                }
            }
            GridRow {
                if showBaseball {
                    Image(systemName: "baseball.fill")
                        .resizable()
                        .frame(width: 9, height: 9)
                        .modifier(SportsTint(sport: .mlb))
                }
                if showFootball {
                    Image(systemName: "football.fill")
                        .resizable()
                        .frame(width: 9, height: 9)
                        .modifier(SportsTint(sport: .nfl))
                }
            }
        }
    }
}

//struct DecorationView_Previews: PreviewProvider {
//    static var previews: some View {
//        DecorationView()
//    }
//}
