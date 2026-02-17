//
//  DayChipStrip.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/15/26.
//

import SwiftUI
import SportsCalModel

struct DayChipStrip: View {
    @Binding var selectedDate: Date
    var datesWithGames: Set<DateComponents>
    var pastDays: Int = 7
    var futureDays: Int = 14
    var sportCountsForDate: ((Date) -> [SportType: Int])? = nil

    private let calendar = Calendar.current

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var days: [Date] {
        (-pastDays...futureDays).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: today)
    }

    private func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func hasGames(_ date: Date) -> Bool {
        let dc = calendar.dateComponents([.day, .month, .year], from: date)
        return datesWithGames.contains { $0.day == dc.day && $0.month == dc.month && $0.year == dc.year }
    }

    private func isNewMonth(_ date: Date, previousDate: Date?) -> Bool {
        guard let prev = previousDate else { return false }
        return calendar.component(.month, from: date) != calendar.component(.month, from: prev)
    }

    @State private var scrollPosition: Date?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.element.timeIntervalSince1970) { index, date in
                    if isNewMonth(date, previousDate: index > 0 ? days[index - 1] : nil) {
                        monthDivider(for: date)
                    }
                    dayChip(for: date)
                        .id(calendar.startOfDay(for: date))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .onAppear {
            scrollPosition = calendar.startOfDay(for: selectedDate)
        }
        .onChange(of: selectedDate) { _, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                scrollPosition = calendar.startOfDay(for: newValue)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDate)
    }

    private func monthDivider(for date: Date) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return Text(formatter.string(from: date).uppercased())
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.secondary)
            .frame(width: 32)
    }

    private func dayChip(for date: Date) -> some View {
        let selected = isSelected(date)
        let today = isToday(date)
        let hasGames = hasGames(date)
        let sportCounts = sportCountsForDate?(date) ?? [:]

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 2) {
                Text(dayAbbreviation(for: date))
                    .font(.caption2)
                    .fontWeight(.medium)
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline)
                    .fontWeight(selected ? .bold : .regular)
                if !sportCounts.isEmpty {
                    SportDensityBar(
                        sportCounts: sportCounts,
                        isSelected: selected
                    )
                } else if today {
                    Circle()
                        .fill(selected ? Color.white : Color.accentColor)
                        .frame(width: 4, height: 4)
                } else if hasGames {
                    Circle()
                        .fill(selected ? Color.white.opacity(0.6) : Color.secondary.opacity(0.4))
                        .frame(width: 4, height: 4)
                } else {
                    Spacer()
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: 40, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.accentColor : Color.clear)
            )
            .foregroundColor(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func dayAbbreviation(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).prefix(3).uppercased()
    }
}

// MARK: - Sport Density Bar

/// Tiny stacked color bar showing proportional game counts per sport
struct SportDensityBar: View {
    let sportCounts: [SportType: Int]
    var isSelected: Bool = false

    private var sortedSports: [(sport: SportType, count: Int)] {
        SportType.allCases.compactMap { sport in
            guard let count = sportCounts[sport], count > 0 else { return nil }
            return (sport: sport, count: count)
        }
    }

    private var totalCount: Int {
        sportCounts.values.reduce(0, +)
    }

    var body: some View {
        if !sortedSports.isEmpty {
            HStack(spacing: 1) {
                ForEach(sortedSports, id: \.sport) { item in
                    let fraction = CGFloat(item.count) / CGFloat(max(totalCount, 1))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isSelected ? Color.white.opacity(0.7) : item.sport.color)
                        .frame(width: max(3, fraction * 28), height: 3)
                }
            }
            .frame(height: 4)
        }
    }
}
