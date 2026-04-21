//
//  DayTimelineView.swift
//  SportsCal (iOS)
//
//  Experimental calendar-style day timeline view.
//  Shows games positioned on a vertical timeline at their start times.
//

import SwiftUI
import SportsCalModel

struct DayTimelineView: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Binding var shouldShowSportsCalProAlert: Bool

    private let hourHeight: CGFloat = 80
    private let timeColumnWidth: CGFloat = 56
    private let calendar = Calendar.current

    // MARK: - Data

    private var dayGames: [GameWithTeams] {
        viewModel.gamesWithTeams(for: selectedDate)
    }

    private var liveGames: [GameWithTeams] {
        guard calendar.isDateInToday(selectedDate) else { return [] }
        return viewModel.liveEventsWithTeams
    }

    private var allGames: [GameWithTeams] {
        var seen: Set<String> = []
        var result: [GameWithTeams] = []
        for gwt in liveGames + dayGames {
            if seen.insert(gwt.id).inserted {
                result.append(gwt)
            }
        }
        return result
    }

    private var timedGames: [GameWithTeams] {
        allGames.filter { $0.game.standardDate != nil }
    }

    private var untimedGames: [GameWithTeams] {
        allGames.filter { $0.game.standardDate == nil }
    }

    private var liveGameIDs: Set<String> {
        Set(viewModel.liveEventsWithTeams.map { $0.id })
    }

    private var timelineRange: (start: Int, end: Int) {
        let hours = timedGames.compactMap { gwt -> Int? in
            guard let date = gwt.game.standardDate else { return nil }
            return calendar.component(.hour, from: date)
        }
        guard let minHour = hours.min(), let maxHour = hours.max() else {
            return (9, 23)
        }
        return (max(0, minHour - 1), min(23, maxHour + 2))
    }

    private func games(forHour hour: Int) -> [GameWithTeams] {
        timedGames.filter { gwt in
            guard let date = gwt.game.standardDate else { return false }
            return calendar.component(.hour, from: date) == hour
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            DayChipStrip(
                selectedDate: $selectedDate,
                datesWithGames: viewModel.datesWithGames(),
                pastDays: daysForDuration(storage.hidePastEvents ? .oneDay : storage.hidePastGamesDuration),
                futureDays: daysForDuration(storage.durations)
            )
            .padding(.horizontal)
            .padding(.bottom, 8)

            if allGames.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            if !untimedGames.isEmpty {
                                untimedSection
                            }
                            timelineContent
                        }
                    }
                    .onAppear {
                        scrollToRelevant(proxy: proxy)
                    }
                    .onChange(of: selectedDate) { _, _ in
                        scrollToRelevant(proxy: proxy)
                    }
                }
            }
        }
        #if os(iOS)
        .gesture(daySwipeGesture)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !calendar.isDateInToday(selectedDate) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = calendar.startOfDay(for: Date())
                        }
                    } label: {
                        Text("Today")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }

    // MARK: - Untimed Section

    private var untimedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.questionmark")
                    .foregroundStyle(.secondary)
                Text("All Day / TBD")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ForEach(untimedGames) { gwt in
                timelineGameCard(for: gwt)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #endif
    }

    // MARK: - Timeline

    private var timelineContent: some View {
        let range = timelineRange
        let hoursWithGames = Set(timedGames.compactMap { gwt -> Int? in
            guard let date = gwt.game.standardDate else { return nil }
            return calendar.component(.hour, from: date)
        })

        return VStack(spacing: 0) {
            ForEach(range.start...range.end, id: \.self) { hour in
                let hourGames = games(forHour: hour)
                let hasGames = !hourGames.isEmpty
                let isNowHour = calendar.isDateInToday(selectedDate) && calendar.component(.hour, from: Date()) == hour
                // Collapse empty hours that aren't adjacent to a game hour or the current hour
                let isAdjacentToGames = hoursWithGames.contains(hour - 1) || hoursWithGames.contains(hour + 1)
                let showFull = hasGames || isNowHour || isAdjacentToGames

                if showFull {
                    VStack(alignment: .leading, spacing: 0) {
                        hourDividerRow(hour: hour, isNowHour: isNowHour)

                        if hasGames {
                            gameCardsRow(hourGames)
                        }
                    }
                    .frame(minHeight: hasGames ? nil : 28)
                    .id(hour)
                } else {
                    // Collapsed spacer for skipped hours
                    hourDividerRow(hour: hour, isNowHour: false)
                        .frame(height: 16)
                        .id(hour)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 40)
    }

    private func hourDividerRow(hour: Int, isNowHour: Bool) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text(hourLabel(hour))
                .font(.caption)
                .foregroundStyle(isNowHour ? .red : .secondary)
                .fontWeight(isNowHour ? .semibold : .regular)
                .frame(width: timeColumnWidth, alignment: .trailing)
                .padding(.trailing, 8)

            if isNowHour {
                nowDivider
            } else {
                Divider()
            }
        }
    }

    private func gameCardsRow(_ hourGames: [GameWithTeams]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(hourGames) { gwt in
                    timelineGameCard(for: gwt)
                        .frame(width: 180)
                }
            }
            .padding(.leading, timeColumnWidth + 8)
            .padding(.trailing, 16)
            .padding(.vertical, 6)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        #if os(iOS)
        .overlay(alignment: .trailing) {
            if hourGames.count > 1 {
                LinearGradient(
                    colors: [.clear, Color(.systemBackground).opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
                .allowsHitTesting(false)
            }
        }
        #endif
    }

    private var nowDivider: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(.red)
                .frame(height: 1.5)
        }
    }

    // MARK: - Game Card

    private func timelineGameCard(for gwt: GameWithTeams) -> some View {
        let game = gwt.game
        let isLive = liveGameIDs.contains(gwt.id)
        let sport = game.sportType

        return NavigationLink {
            destinationView(for: gwt)
        } label: {
            HStack(spacing: 6) {
                // Sport color bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(sport?.color ?? .gray)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 2) {
                    // Team names
                    if game.isIndividualSport || game.isRace || game.isTennisMatch {
                        Text(game.strHomeTeam)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    } else {
                        Text(game.strAwayTeam)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text(game.strHomeTeam)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }

                    // Status line
                    HStack(spacing: 4) {
                        if isLive {
                            Text("LIVE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(.red, in: Capsule())
                        }
                        if let homeScore = game.intHomeScore, let awayScore = game.intAwayScore,
                           game.strStatus != "pre" && game.strStatus != "NS" {
                            Text("\(awayScore)-\(homeScore)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let date = game.standardDate {
                            GameTimeLabel(date: date)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isLive ? .red.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Destination

    @ViewBuilder
    private func destinationView(for gwt: GameWithTeams) -> some View {
        let game = gwt.game
        if game.isRace {
            RaceDetailView(game: game)
                .environment(viewModel)
                .environment(favorites)
        } else if game.isTennisMatch {
            TennisMatchDetailView(game: game)
                .environment(viewModel)
                .environment(favorites)
        } else if game.isIndividualSport {
            TournamentDetailView(game: game)
                .environment(viewModel)
                .environment(favorites)
        } else if let homeTeam = gwt.homeTeam, let awayTeam = gwt.awayTeam {
            GameDetailView(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                .environment(viewModel)
                .environment(favorites)
        }
    }

    // MARK: - Helpers

    private func hourLabel(_ hour: Int) -> String {
        let adjustedHour = hour % 12
        let displayHour = adjustedHour == 0 ? 12 : adjustedHour
        let period = hour < 12 ? "AM" : "PM"
        return "\(displayHour) \(period)"
    }

    // MARK: - Scroll

    private func scrollToRelevant(proxy: ScrollViewProxy) {
        if calendar.isDateInToday(selectedDate) {
            let currentHour = calendar.component(.hour, from: Date())
            let range = timelineRange
            let targetHour = max(range.start, min(range.end, currentHour - 1))
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(targetHour, anchor: .top)
            }
        } else if let firstHour = timedGames.compactMap({ $0.game.standardDate }).min().map({ calendar.component(.hour, from: $0) }) {
            let target = max(timelineRange.start, firstHour - 1)
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(calendar.isDateInToday(selectedDate)
                 ? "No games scheduled for today"
                 : "No games scheduled for \(formattedSelectedDate)")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Navigation

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                navigateDay(by: horizontal < 0 ? 1 : -1)
            }
    }

    private func navigateDay(by offset: Int) {
        guard let newDate = calendar.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = newDate
        }
    }

    private func daysForDuration(_ duration: Durations) -> Int {
        let today = calendar.startOfDay(for: Date())
        let target: Date?
        switch duration {
        case .oneDay:     target = calendar.date(byAdding: .day, value: 1, to: today)
        case .oneWeek:    target = calendar.date(byAdding: .weekOfYear, value: 1, to: today)
        case .twoWeeks:   target = calendar.date(byAdding: .weekOfYear, value: 2, to: today)
        case .threeWeeks: target = calendar.date(byAdding: .weekOfYear, value: 3, to: today)
        case .oneMonth:   target = calendar.date(byAdding: .month, value: 1, to: today)
        case .twoMonths:  target = calendar.date(byAdding: .month, value: 2, to: today)
        case .sixMonths:  target = calendar.date(byAdding: .month, value: 6, to: today)
        case .oneYear:    target = calendar.date(byAdding: .year, value: 1, to: today)
        }
        guard let target else { return 14 }
        return max(1, calendar.dateComponents([.day], from: today, to: target).day ?? 14)
    }

    private var formattedSelectedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDate)
    }
}

#Preview {
    NavigationStack {
        DayTimelineView(shouldShowSportsCalProAlert: .constant(false))
            .environment(GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites()))
            .environment(UserDefaultStorage())
            .environment(Favorites())
            .navigationTitle("Timeline")
    }
}
