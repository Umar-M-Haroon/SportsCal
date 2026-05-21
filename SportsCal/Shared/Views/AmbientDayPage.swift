//
//  AmbientDayPage.swift
//  SportsCal (iOS)
//
//  Dark airport-departures-board variant of DayPage. Reads the same view-model
//  data (live events, today's games, favorites) and renders each game as a
//  single row with TIME · MATCH · STATUS columns.
//

import SwiftUI
import SportsCalModel

struct AmbientDayPage: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current

    private static let bigDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    private var isToday: Bool {
        calendar.isDateInToday(selectedDate)
    }

    private var liveRows: [GameWithTeams] {
        guard isToday else { return [] }
        return viewModel.liveEventsWithTeams
    }

    private var dayRows: [GameWithTeams] {
        viewModel.gamesWithTeams(for: selectedDate)
    }

    /// Combined ordered list: live (favorites first) → upcoming (favorites first, by time) → finals
    private var orderedRows: [GameWithTeams] {
        let liveIDs = Set(liveRows.map(\.id))

        let live = liveRows.sorted { a, b in
            let af = favorites.contains(a.game)
            let bf = favorites.contains(b.game)
            if af != bf { return af }
            return (a.game.standardDate ?? .distantFuture) < (b.game.standardDate ?? .distantFuture)
        }

        let nonLive = dayRows.filter { !liveIDs.contains($0.id) }
        let upcoming = nonLive
            .filter { !$0.game.hasDoneStatus }
            .sorted { a, b in
                let af = favorites.contains(a.game)
                let bf = favorites.contains(b.game)
                if af != bf { return af }
                return (a.game.standardDate ?? .distantFuture) < (b.game.standardDate ?? .distantFuture)
            }
        let finals = nonLive
            .filter { $0.game.hasDoneStatus }
            .sorted { a, b in
                (a.game.standardDate ?? .distantPast) > (b.game.standardDate ?? .distantPast)
            }

        return live + upcoming + finals
    }

    var body: some View {
        ZStack(alignment: .top) {
            AmbientPalette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                AmbientHeader(
                    eyebrow: isToday ? "TODAY" : "DAY",
                    title: Self.bigDateFormatter.string(from: selectedDate).lowercased(),
                    trailing: liveRows.isEmpty
                        ? nil
                        : AnyView(AmbientLivePill(count: liveRows.count))
                )

                weekStrip
                    .padding(.top, 2)
                    .padding(.bottom, 10)

                columnHeader

                if orderedRows.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(orderedRows, id: \.id) { gwt in
                                NavigationLink {
                                    AdaptiveGameDetail(gwt: gwt)
                                } label: {
                                    row(for: gwt)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bottom closing line so the last row has a divider on both sides.
                            Rectangle()
                                .fill(AmbientPalette.divider)
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        #if !os(macOS)
        .toolbarBackground(AmbientPalette.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
    }

    // MARK: - Column header

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("TIME")
                .frame(width: 48, alignment: .leading)
            Spacer().frame(width: 16)
            Text("MATCH")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("STATUS")
        }
        .font(.ambientMono(9, weight: .regular))
        .tracking(1)
        .foregroundStyle(AmbientPalette.muted.opacity(0.7))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Row

    private func row(for gwt: GameWithTeams) -> some View {
        let game = gwt.game
        let isLive = liveRows.contains(where: { $0.id == gwt.id })
        let isFinal = !isLive && game.hasDoneStatus
        let fav = favorites.contains(game)

        return AmbientDepartureRow(
            time: AmbientFormat.timeText(for: game.standardDate, isLive: isLive, isFinal: isFinal),
            sport: game.sportType,
            matchText: AmbientFormat.matchText(game: game, away: gwt.awayTeam, home: gwt.homeTeam),
            statusText: statusText(for: game, isLive: isLive, isFinal: isFinal),
            isLive: isLive,
            isFavorite: fav,
            isFinal: isFinal
        )
    }

    private func statusText(for game: Game, isLive: Bool, isFinal: Bool) -> String {
        if isLive {
            // Prefer period progress (e.g. "3Q", "2P", "TOP 7") when we have it.
            if let progress = game.strProgress, !progress.isEmpty {
                return progress
            }
            if let status = game.strStatus, !status.isEmpty {
                return status
            }
            return "LIVE"
        }
        if isFinal {
            if let status = game.strStatus, status.lowercased().contains("ot") { return "FINAL · OT" }
            return "FINAL"
        }
        // Upcoming — within 30 min = SOON
        if let date = game.standardDate {
            let diff = date.timeIntervalSinceNow
            if diff > 0 && diff < 30 * 60 { return "SOON" }
        }
        return game.sportType?.displayName.uppercased() ?? ""
    }

    // MARK: - Week strip (minimal dark variant)

    private var weekStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(-3...10, id: \.self) { offset in
                    dayChip(offset: offset)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func dayChip(offset: Int) -> some View {
        let today = calendar.startOfDay(for: Date())
        let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isTodayChip = calendar.isDate(date, inSameDayAs: today)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDate = calendar.startOfDay(for: date)
            }
        } label: {
            VStack(spacing: 3) {
                Text(weekdayAbbr(date))
                    .font(.ambientMono(9))
                    .foregroundStyle(selected ? AmbientPalette.bg : AmbientPalette.muted)
                Text(dayNumber(date))
                    .font(.ambientDisplay(14, weight: selected ? .bold : .semibold))
                    .foregroundStyle(selected ? AmbientPalette.bg : AmbientPalette.ink)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? AmbientPalette.ink : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isTodayChip && !selected ? AmbientPalette.highlight : AmbientPalette.faint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func weekdayAbbr(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private func dayNumber(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sportscourt")
                .font(.system(size: 32))
                .foregroundStyle(AmbientPalette.muted)
            Text("NO GAMES")
                .font(.ambientMono(11, weight: .bold))
                .tracking(2)
                .foregroundStyle(AmbientPalette.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
