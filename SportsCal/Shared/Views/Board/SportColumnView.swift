//
//  SportColumnView.swift
//  SportsCal (iOS)
//

import SwiftUI
import SportsCalModel

struct SportColumnView<GameContent: View>: View {
    let sport: SportType
    let liveGames: [GameWithTeams]
    let otherGames: [GameWithTeams]
    let favorites: Favorites
    @ViewBuilder let gameContent: (GameWithTeams, Bool) -> GameContent

    @State private var isCollapsed: Bool = false

    private var totalCount: Int { liveGames.count + otherGames.count }
    private var isEmpty: Bool { totalCount == 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !isCollapsed && !isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 8) {
                        ForEach(liveGames) { gwt in
                            BoardGameCard(isFavorite: favorites.contains(gwt.game), isLive: true) {
                                gameContent(gwt, true)
                            }
                        }
                        ForEach(otherGames) { gwt in
                            BoardGameCard(isFavorite: favorites.contains(gwt.game), isLive: false) {
                                gameContent(gwt, false)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            if isEmpty { isCollapsed = true }
        }
    }

    private var header: some View {
        Button {
            guard !isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: sport.systemImage)
                    .foregroundStyle(sport.color)
                Text(sport.displayName)
                    .fontWeight(.semibold)
                Text("\(totalCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !isEmpty {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}
