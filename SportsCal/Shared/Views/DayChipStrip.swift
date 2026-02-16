//
//  DayChipStrip.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/15/26.
//

import SwiftUI

struct DayChipStrip: View {
    @Binding var selectedDate: Date
    var datesWithGames: Set<DateComponents>
    var pastDays: Int = 7
    var futureDays: Int = 14

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

    var body: some View {
        ScrollViewReader { proxy in
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
            .onAppear {
                proxy.scrollTo(calendar.startOfDay(for: selectedDate), anchor: .center)
            }
            .onChange(of: selectedDate) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(calendar.startOfDay(for: newValue), anchor: .center)
                }
            }
        }
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
                if today {
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
