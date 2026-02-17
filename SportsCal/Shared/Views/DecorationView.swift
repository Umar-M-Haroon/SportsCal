//
//  DecorationView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/19/23.
//

import SwiftUI
import SportsCalModel

struct DecorationView: View {
    var sportTypes: Set<SportType>
    var gameCount: Int
    var showFavorites: Bool

    private var iconSize: CGFloat {
        sportTypes.count >= 5 ? 6 : 8
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SportType.allCases.filter { sportTypes.contains($0) }, id: \.self) { sport in
                Image(systemName: sport.systemImage)
                    .font(.system(size: iconSize))
                    .foregroundStyle(sport.color)
            }
            if showFavorites {
                Image(systemName: "star.fill")
                    .font(.system(size: iconSize))
                    .foregroundColor(.yellow)
            }
        }
    }
}
