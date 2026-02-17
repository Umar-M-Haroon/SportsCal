//
//  WeekTimelineView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/16/26.
//

import SwiftUI
import SportsCalModel

/// Vertical time-of-day (6am–midnight) x 7-day grid with colored pills per game.
struct WeekTimelineView: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    let selectedDate: Date
    var onGameTap: ((Game) -> Void)? = nil

    private let calendar = Calendar.current
    private let startHour = 6  // 6 AM
    private let endHour = 24   // midnight
    private let hourHeight: CGFloat = 40
    private let dayColumnWidth: CGFloat = 50

    private var weekDates: [Date] {
        let startOfWeek = calendar.startOfDay(for: selectedDate)
        return (-3...3).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startOfWeek)
        }
    }

    private func gamesForDate(_ date: Date) -> [Game] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return (viewModel.filteredGames ?? []).filter { game in
            guard let gameDate = game.standardDate else { return false }
            return gameDate >= start && gameDate < end
        }
    }

    private var totalHeight: CGFloat {
        CGFloat(endHour - startHour) * hourHeight
    }

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "calendar.day.timeline.left")
                        .foregroundColor(.accentColor)
                    Text("Week Timeline")
                        .font(.headline)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        // Time labels column
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(startHour..<endHour, id: \.self) { hour in
                                Text(hourLabel(hour))
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .frame(height: hourHeight, alignment: .top)
                            }
                        }
                        .frame(width: 36)

                        // Day columns
                        ForEach(weekDates, id: \.timeIntervalSince1970) { date in
                            DayColumnView(
                                date: date,
                                games: gamesForDate(date),
                                favorites: favorites,
                                isToday: calendar.isDateInToday(date),
                                startHour: startHour,
                                hourHeight: hourHeight,
                                totalHeight: totalHeight,
                                onGameTap: onGameTap
                            )
                            .frame(width: dayColumnWidth)
                        }
                    }
                }
                .frame(height: totalHeight + 20) // extra for header
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0 { return "12a" }
        if h < 12 { return "\(h)a" }
        if h == 12 { return "12p" }
        return "\(h - 12)p"
    }
}

// MARK: - Day Column

private struct DayColumnView: View {
    let date: Date
    let games: [Game]
    let favorites: Favorites
    let isToday: Bool
    let startHour: Int
    let hourHeight: CGFloat
    let totalHeight: CGFloat
    var onGameTap: ((Game) -> Void)?

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            // Day header
            VStack(spacing: 1) {
                Text(dayAbbr)
                    .font(.system(size: 9, weight: .medium))
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 11, weight: isToday ? .bold : .regular))
            }
            .foregroundColor(isToday ? .accentColor : .primary)
            .frame(height: 24)

            // Game pills in a time grid
            ZStack(alignment: .top) {
                // Grid lines (hourly)
                ForEach(0..<(24 - startHour), id: \.self) { i in
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 0.5)
                        .offset(y: CGFloat(i) * hourHeight)
                }

                // Game pills
                ForEach(games, id: \.id) { game in
                    if let gameDate = game.standardDate {
                        let hour = calendar.component(.hour, from: gameDate)
                        let minute = calendar.component(.minute, from: gameDate)
                        let offset = CGFloat(hour - startHour) * hourHeight + CGFloat(minute) / 60 * hourHeight
                        let isFav = favorites.contains(game)
                        let sport = game.sportType

                        Button {
                            onGameTap?(game)
                        } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill((sport?.color ?? .gray).opacity(0.8))
                                .frame(width: 38, height: max(hourHeight * 0.8, 16))
                                .overlay {
                                    if isFav {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 6))
                                            .foregroundColor(.white)
                                            .offset(x: 12, y: -4)
                                    }
                                }
                                .overlay {
                                    if game.strStatus == "in" {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 5, height: 5)
                                            .offset(x: -14, y: -4)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .offset(y: max(0, offset))
                    }
                }
            }
            .frame(height: totalHeight)
        }
    }

    private var dayAbbr: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return String(formatter.string(from: date).prefix(2))
    }
}
