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
    /// A full-width column with the next game date.
    case column
    /// A narrow strip at the end: icon and next date.
    case rail
    /// One summary strip above the board, a chip per sport.
    case tray
    /// A full-width column previewing the sport's next game day.
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .column: "Full Column"
        case .rail: "Narrow Rail"
        case .tray: "Summary Strip"
        case .preview: "Next-Day Preview"
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
    @ViewBuilder let gameContent: (GameWithTeams, Bool) -> GameContent

    #if os(macOS)
    @AppStorage("board.emptyStyle") private var emptyStyle: BoardEmptyStyle = .rail
    #else
    private let emptyStyle: BoardEmptyStyle = .column
    #endif

    private static var railWidth: CGFloat { 76 }

    var body: some View {
        let filled = columns.filter { !$0.isEmpty }
        let empty = columns.filter(\.isEmpty)
        VStack(spacing: 0) {
            if emptyStyle == .tray, !empty.isEmpty {
                emptyTray(empty)
            }
            GeometryReader { geometry in
                let fullColumns: [BoardColumn] = switch emptyStyle {
                case .column, .preview: filled + empty
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
                                upcomingGames: emptyStyle == .preview ? column.upcomingGames : [],
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

    /// A narrow strip for a sport with no games: icon, name, next date.
    private func emptyRail(_ column: BoardColumn) -> some View {
        Button {
            if let date = column.nextGameDate { onJumpToDate(date) }
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
                        if let date = column.nextGameDate { onJumpToDate(date) }
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
                    .disabled(column.nextGameDate == nil)
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
