//
//  SportColumnView.swift
//  SportsCal (iOS)
//

import SwiftUI
import SportsCalModel

struct SportColumnView<GameContent: View>: View {
    let sport: SportType
    /// The column's games, in display order; titled per competition for soccer
    /// and cricket (see `BoardColumn.sections`).
    let sections: [BoardColumnSection]
    let favorites: Favorites
    let nextGameDate: Date?
    let onJumpToDate: (Date) -> Void
    @ViewBuilder let gameContent: (GameWithTeams, Bool) -> GameContent

    @State private var isCollapsed: Bool = false

    private var totalCount: Int { sections.reduce(0) { $0 + $1.count } }
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
        // Not a Material: a material background gives every `.secondary`/hierarchical
        // style inside the column vibrancy, which blends it through the opaque game
        // cards — losing scores, team codes and "Final" rendered invisible on iPad/Mac.
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .onAppear { isCollapsed = UserDefaults.standard.bool(forKey: collapseKey) }
    }

    private var gamesBody: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 8) {
                ForEach(sections) { section in
                    if let league = section.league {
                        sectionHeader(league, count: section.count)
                    }
                    ForEach(section.liveGames) { gwt in
                        BoardGameCard(gameID: gwt.id, isFavorite: favorites.contains(gwt.game), isLive: true) {
                            gameContent(gwt, true)
                        }
                    }
                    ForEach(section.otherGames) { gwt in
                        BoardGameCard(gameID: gwt.id, isFavorite: favorites.contains(gwt.game), isLive: false) {
                            gameContent(gwt, false)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
        }
    }

    /// A competition subheading inside a soccer or cricket column.
    private func sectionHeader(_ league: Leagues, count: Int) -> some View {
        HStack(spacing: 5) {
            Text(league.competitionShortName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        // Space the heading off the previous group's last card.
        .padding(.top, sections.first?.league == league ? 0 : 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
