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
    let nextGameDate: Date?
    let onJumpToDate: (Date) -> Void
    @ViewBuilder let gameContent: (GameWithTeams, Bool) -> GameContent

    @State private var isCollapsed: Bool = false

    private var totalCount: Int { liveGames.count + otherGames.count }
    private var isEmpty: Bool { totalCount == 0 }

    /// Per-sport persisted collapse state (survives relaunch).
    private var collapseKey: String { "board.column.collapsed.\(sport.rawValue)" }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !isCollapsed {
                if isEmpty {
                    emptyBody
                } else {
                    gamesBody
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { isCollapsed = UserDefaults.standard.bool(forKey: collapseKey) }
    }

    private var gamesBody: some View {
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

    private var emptyBody: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .foregroundStyle(.secondary)
            if let date = nextGameDate {
                Button {
                    onJumpToDate(date)
                } label: {
                    VStack(spacing: 2) {
                        Text("Next \(sport.displayName) game")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(date.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated)))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(sport.color)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("No upcoming \(sport.displayName) games")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCollapsed.toggle()
            }
            UserDefaults.standard.set(isCollapsed, forKey: collapseKey)
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
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        // Drag the header to reorder columns (handled by the board's drop target).
        .draggable(sport.rawValue)
    }
}
