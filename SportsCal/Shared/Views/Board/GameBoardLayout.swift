//
//  GameBoardLayout.swift
//  SportsCal (iOS)
//

import SwiftUI
import SportsCalModel

struct BoardColumn: Identifiable {
    var id: SportType { sport }
    let sport: SportType
    let liveGames: [GameWithTeams]
    let otherGames: [GameWithTeams]
}

struct GameBoardLayout<GameContent: View>: View {
    let columns: [BoardColumn]
    let favorites: Favorites
    @ViewBuilder let gameContent: (GameWithTeams, Bool) -> GameContent

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = computeColumnWidth(
                availableWidth: geometry.size.width,
                columnCount: columns.count
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(columns) { column in
                        SportColumnView(
                            sport: column.sport,
                            liveGames: column.liveGames,
                            otherGames: column.otherGames,
                            favorites: favorites,
                            gameContent: gameContent
                        )
                        .frame(width: columnWidth)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func computeColumnWidth(availableWidth: CGFloat, columnCount: Int) -> CGFloat {
        guard columnCount > 0 else { return 300 }
        let padding: CGFloat = 32
        let spacing: CGFloat = 12
        let usable = availableWidth - padding - CGFloat(columnCount - 1) * spacing
        let fittable = max(1, Int(usable / 300))

        if columnCount <= fittable {
            return usable / CGFloat(columnCount)
        } else {
            return 300
        }
    }
}
