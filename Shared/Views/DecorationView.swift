//
//  DecorationView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/15/23.
//

import SwiftUI

struct DecorationView: View {
    var showBasketball: Bool
    var showSoccer: Bool
    var showHockey: Bool
    var showBaseball: Bool
    var showFootball: Bool
    var body: some View {
        HStack(spacing: 0) {
            if showBasketball {
                Image(systemName: "basketball.fill")
                    .resizable()
                    .frame(width: 10, height: 10)
            }
            if showSoccer {
                Image(systemName: "soccerball")
                    .resizable()
                    .frame(width: 10, height: 10)
            }
            if showHockey {
                Image(systemName: "hockey.puck.fill")
                    .resizable()
                    .frame(width: 10, height: 10)
            }
            if showBaseball {
                Image(systemName: "baseball.fill")
                    .resizable()
                    .frame(width: 10, height: 10)
            }
            if showFootball {
                Image(systemName: "football.fill")
                    .resizable()
                    .frame(width: 10, height: 10)
            }
        }
    }
}

//struct DecorationView_Previews: PreviewProvider {
//    static var previews: some View {
//        DecorationView()
//    }
//}
