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
    let nextGameDate: Date?
}

struct GameBoardLayout<GameContent: View>: View {
    let columns: [BoardColumn]
    let favorites: Favorites
    let onJumpToDate: (Date) -> Void
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
                            nextGameDate: column.nextGameDate,
                            onJumpToDate: onJumpToDate,
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
        #if os(macOS)
        // Cap at 2 columns visible on macOS; extra sports scroll horizontally.
        let maxColumns = 2
        let visibleCount = min(columnCount, maxColumns)
        let visibleUsable = availableWidth - padding - CGFloat(visibleCount - 1) * spacing
        return visibleUsable / CGFloat(visibleCount)
        #else
        let fittable = max(1, Int(usable / 300))
        if columnCount <= fittable {
            return usable / CGFloat(columnCount)
        } else {
            return 300
        }
        #endif
    }
}
