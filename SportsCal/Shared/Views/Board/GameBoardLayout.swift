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
    /// The sport's games on `nextGameDate`, for an empty column's preview.
    var upcomingGames: [GameWithTeams] = []

    var isEmpty: Bool { liveGames.isEmpty && otherGames.isEmpty }
}

/// How the Mac board shows a sport with nothing on the selected day. Sports with
/// games always come first; this only decides what the rest look like.
enum BoardEmptyStyle: String, CaseIterable, Identifiable {
    /// A full-width column with the next game date (iOS never shows these).
    case column
    /// A narrow strip at the end: icon and next date.
    case rail
    /// One summary strip above the board, a chip per sport.
    case tray

    var id: String { rawValue }

    /// The choices offered in the Games menu.
    static let menuChoices: [BoardEmptyStyle] = [.rail, .tray]

    var title: String {
        switch self {
        case .column: "Full Columns"
        case .rail: "Narrow Rails"
        case .tray: "Summary Strip"
        }
    }
}

struct GameBoardLayout<GameContent: View>: View {
    let columns: [BoardColumn]
    let favorites: Favorites
    let onJumpToDate: (Date) -> Void
    /// Drag a column header onto another column to reorder sports. Receives
    /// (movedSport, targetSport). Nil disables reordering (e.g. on iOS).
    var onMoveSport: ((SportType, SportType) -> Void)? = nil
    /// Turns a sport off from an empty rail/chip's context menu.
    var onHideSport: ((SportType) -> Void)? = nil
    @ViewBuilder let gameContent: (GameWithTeams, Bool) -> GameContent

    #if os(macOS)
    @AppStorage("board.emptyStyle") private var emptyStyle: BoardEmptyStyle = .rail
    /// Live games in a strip across the top instead of inside their columns.
    @AppStorage("board.liveFirst") private var liveFirst = true
    /// The empty sport whose next game day is peeked in a popover.
    @State private var peekedSport: SportType?
    #else
    private let emptyStyle: BoardEmptyStyle = .column
    private let liveFirst = false
    @State private var peekedSport: SportType?
    #endif

    private static var railWidth: CGFloat { 76 }

    var body: some View {
        // Live-first: every live game moves to the strip, and the columns keep only
        // upcoming and finished games, so nothing shows twice.
        let liveStrip = liveFirst ? columns.flatMap(\.liveGames) : []
        let columns = liveStrip.isEmpty ? self.columns : self.columns.map {
            BoardColumn(sport: $0.sport, liveGames: [], otherGames: $0.otherGames,
                        nextGameDate: $0.nextGameDate, upcomingGames: $0.upcomingGames)
        }
        let filled = columns.filter { !$0.isEmpty }
        // Rails and chips are for "not today": an off-season sport with nothing
        // scheduled stays out of the board and is still a click away in the sidebar.
        let empty = columns.filter { $0.isEmpty && ($0.nextGameDate != nil || emptyStyle == .column) }
        VStack(spacing: 0) {
            if !liveStrip.isEmpty {
                liveStripView(liveStrip)
            }
            if emptyStyle == .tray, !empty.isEmpty {
                emptyTray(empty)
            }
            GeometryReader { geometry in
                let fullColumns: [BoardColumn] = switch emptyStyle {
                case .column: filled + empty
                case .rail, .tray: filled
                }
                let rails = emptyStyle == .rail ? empty : []
                let columnWidth = computeColumnWidth(
                    availableWidth: geometry.size.width
                        - CGFloat(rails.count) * (Self.railWidth + 12),
                    columnCount: fullColumns.count
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(fullColumns) { column in
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
                        ForEach(rails) { column in
                            emptyRail(column)
                                .frame(width: Self.railWidth)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                }
                // Rest on whole columns, never half of one.
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    /// Live games across every sport, favorites first.
    private func liveStripView(_ live: [GameWithTeams]) -> some View {
        let ordered = live.sorted { favorites.contains($0.game) && !favorites.contains($1.game) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text("Live")
                    .fontWeight(.semibold)
                Text("\(live.count)")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(ordered) { gwt in
                        BoardGameCard(gameID: gwt.id, isFavorite: favorites.contains(gwt.game), isLive: true) {
                            gameContent(gwt, true)
                        }
                        .frame(width: 300)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            // A horizontal ScrollView takes all the height it's offered; hug the cards.
            .fixedSize(horizontal: false, vertical: true)
        }
        // The same panel as a sport column, so the cards stand off the window.
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// A narrow strip for a sport with no games: icon, name, next date.
    private func emptyRail(_ column: BoardColumn) -> some View {
        Button {
            peekedSport = column.sport
        } label: {
            VStack(spacing: 10) {
                Image(systemName: column.sport.systemImage)
                    .font(.title3)
                    .foregroundStyle(column.sport.color)
                Text(column.sport.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Divider()
                if let date = column.nextGameDate {
                    VStack(spacing: 2) {
                        Text("Next")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(date.formatted(.dateTime.day()))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(column.sport.color)
                    }
                } else {
                    Text("None scheduled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(column.nextGameDate == nil)
        .help(column.nextGameDate.map { "No \(column.sport.displayName) today. Next game \($0.formatted(date: .complete, time: .omitted))" } ?? "")
        .modifier(EmptySportActions(
            column: column,
            peekedSport: $peekedSport,
            firstSport: columns.first?.sport,
            onJumpToDate: onJumpToDate,
            onMoveSport: onMoveSport,
            onHideSport: onHideSport,
            peek: { peekView(column) }
        ))
    }

    /// The next game day as real board cards. Clicking one shows it in the
    /// inspector beside today's board.
    private func peekView(_ column: BoardColumn) -> AnyView {
        AnyView(NextGameDayPeek(
            column: column,
            favorites: favorites,
            card: { gwt in
                AnyView(
                    BoardGameCard(gameID: gwt.id, isFavorite: favorites.contains(gwt.game), isLive: false) {
                        gameContent(gwt, false)
                    }
                    .simultaneousGesture(TapGesture().onEnded { peekedSport = nil })
                )
            },
            goToDay: { date in
                peekedSport = nil
                onJumpToDate(date)
            }
        ))
    }


    /// One line above the board listing the sports with nothing today.
    private func emptyTray(_ empty: [BoardColumn]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("No games today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(empty) { column in
                    Button {
                        peekedSport = column.sport
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: column.sport.systemImage)
                                .foregroundStyle(column.sport.color)
                            Text(column.sport.displayName)
                                .fontWeight(.medium)
                            if let date = column.nextGameDate {
                                Text("next \(date.formatted(.dateTime.weekday(.abbreviated).day()))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .modifier(EmptySportActions(
                        column: column,
                        peekedSport: $peekedSport,
                        firstSport: columns.first?.sport,
                        onJumpToDate: onJumpToDate,
                        onMoveSport: onMoveSport,
                        onHideSport: onHideSport,
                        peek: { peekView(column) }
                    ))
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
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
        // Fit as many whole columns of at least 280pt as the width allows and share
        // the width between them, so the last visible column is never cut off.
        let content = availableWidth - padding
        let minimum: CGFloat = 280
        let fittable = max(1, Int((content + spacing) / (minimum + spacing)))
        let shown = min(columnCount, fittable)
        return (content - CGFloat(shown - 1) * spacing) / CGFloat(shown)
        #endif
    }
}

/// Peek popover + context menu shared by an empty sport's rail and chip.
private struct EmptySportActions: ViewModifier {
    let column: BoardColumn
    @Binding var peekedSport: SportType?
    let firstSport: SportType?
    let onJumpToDate: (Date) -> Void
    let onMoveSport: ((SportType, SportType) -> Void)?
    let onHideSport: ((SportType) -> Void)?
    let peek: () -> AnyView

    private var isPeeking: Binding<Bool> {
        Binding(
            get: { peekedSport == column.sport },
            set: { if !$0, peekedSport == column.sport { peekedSport = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .popover(isPresented: isPeeking, arrowEdge: .bottom) { peek() }
            .contextMenu {
                if let date = column.nextGameDate {
                    Button("Go to \(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))") {
                        onJumpToDate(date)
                    }
                }
                if let onMoveSport, let firstSport, firstSport != column.sport {
                    Button("Move to Front") { onMoveSport(column.sport, firstSport) }
                }
                if let onHideSport {
                    Divider()
                    Button("Hide \(column.sport.displayName)") { onHideSport(column.sport) }
                }
            }
    }
}

/// The sport's next game day, without moving the board off today.
private struct NextGameDayPeek: View {
    let column: BoardColumn
    let favorites: Favorites
    let card: (GameWithTeams) -> AnyView
    let goToDay: (Date) -> Void

    private static let limit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if column.upcomingGames.isEmpty {
                Text("No games listed yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        // Favorites first: the game you care about leads the peek.
                        ForEach(ordered.prefix(Self.limit)) { gwt in card(gwt) }
                    }
                    .padding(.horizontal, 10)
                }
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let date = column.nextGameDate {
                Divider().padding(.top, 10)
                HStack {
                    if column.upcomingGames.count > Self.limit {
                        Text("+\(column.upcomingGames.count - Self.limit) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        goToDay(date)
                    } label: {
                        Label("Go to \(date.formatted(.dateTime.weekday(.wide)))", systemImage: "arrow.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 360)
        // The popover hands keyboard focus to its first card, which drew a focus
        // ring around it as if it were selected.
        .focusEffectDisabled()
    }

    private var ordered: [GameWithTeams] {
        column.upcomingGames.sorted { favorites.contains($0.game) && !favorites.contains($1.game) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: column.sport.systemImage)
                .foregroundStyle(column.sport.color)
            VStack(alignment: .leading, spacing: 1) {
                Text("Next \(column.sport.displayName)")
                    .font(.headline)
                if let date = column.nextGameDate {
                    Text(subtitle(for: date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    /// "Thursday, Nov 19 · in 2 days · 1 game"
    private func subtitle(for date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)).day ?? 0
        let relative = switch days {
        case 1: "tomorrow"
        case 2...6: "in \(days) days"
        default: date.formatted(.relative(presentation: .named))
        }
        let count = column.upcomingGames.count
        let games = count == 1 ? "1 game" : "\(count) games"
        return "\(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) · \(relative) · \(games)"
    }
}
