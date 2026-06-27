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
    /// Drag a column header onto another column to reorder sports. Receives
    /// (movedSport, targetSport). Nil disables reordering (e.g. on iOS).
    var onMoveSport: ((SportType, SportType) -> Void)? = nil
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
                        .dropDestination(for: String.self) { items, _ in
                            guard let onMoveSport,
                                  let raw = items.first,
                                  let source = SportType(rawValue: raw),
                                  source != column.sport else { return false }
                            onMoveSport(source, column.sport)
                            return true
                        }
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
        // Fill the (wide) Mac window: fit as many ~320pt columns as possible,
        // distributing evenly when they all fit, else fixed-width + scroll.
        let target: CGFloat = 320
        let fittable = max(1, Int(usable / target))
        if columnCount <= fittable {
            return usable / CGFloat(columnCount)
        } else {
            return target
        }
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
