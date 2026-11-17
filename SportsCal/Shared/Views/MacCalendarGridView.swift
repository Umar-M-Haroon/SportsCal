//
//  MacCalendarGridView.swift
//  SportsCal
//
//  Month-grid date jumper for the Mac calendar popover (⇧⌘D / calendar
//  button in DayChipStrip). Replaces the plain graphical DatePicker with a
//  grid that shows per-day sport-colored density dots, month paging, and a
//  Today shortcut — the Mac stand-in for the iOS Calendar tab.
//

#if os(macOS)
import SwiftUI
import SportsCalModel

struct MacCalendarGridView: View {
    @Binding var selectedDate: Date
    /// Called after a day is picked so the hosting popover can dismiss.
    var onSelect: () -> Void = {}

    @Environment(GameViewModel.self) private var viewModel

    @State private var displayedMonth: Date = Date()
    private let calendar = Calendar.current

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdayRow
            dayGrid
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { displayedMonth = selectedDate }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(Self.monthTitleFormatter.string(from: displayedMonth))
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("Previous month")
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help("Next month")
        }
    }

    private var footer: some View {
        HStack {
            Button("Today") {
                pick(Date())
            }
            .buttonStyle(.link)
            Spacer()
        }
    }

    // MARK: - Grid

    private var weekdayRow: some View {
        let symbols = calendar.veryShortWeekdaySymbols
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        let days = monthGridDays
        let dots = sportDotsByDay
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(days, id: \.timeIntervalSince1970) { day in
                dayCell(day, dots: dots[calendar.dateComponents([.year, .month, .day], from: day)] ?? [])
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date, dots: [Color]) -> some View {
        let inMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)

        Button {
            pick(day)
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout.monospacedDigit())
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(
                        isSelected ? Color.white
                        : isToday ? Color.accentColor
                        : inMonth ? Color.primary : Color.secondary.opacity(0.5)
                    )
                HStack(spacing: 2) {
                    ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color.opacity(inMonth ? 1 : 0.4))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(day.formatted(date: .complete, time: .omitted))
    }

    // MARK: - Data

    /// All grid days covering the displayed month, padded to full weeks.
    private var monthGridDays: [Date] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let monthRange = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let leading = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let total = leading + monthRange.count
        let rows = Int(ceil(Double(total) / 7.0))
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) else { return [] }
        return (0..<(rows * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    /// Up to 3 sport colors per day in the displayed month window, ordered by
    /// how many games that sport has that day (mirrors the iOS calendar's
    /// per-sport decoration dots).
    private var sportDotsByDay: [DateComponents: [Color]] {
        guard let games = viewModel.filteredGames, !games.isEmpty,
              let windowStart = monthGridDays.first,
              let windowEnd = monthGridDays.last.flatMap({ calendar.date(byAdding: .day, value: 1, to: $0) })
        else { return [:] }

        var counts: [DateComponents: [SportType: Int]] = [:]
        for game in games {
            guard let date = game.standardDate,
                  date >= windowStart, date < windowEnd,
                  let sport = game.sportType else { continue }
            let key = calendar.dateComponents([.year, .month, .day], from: date)
            counts[key, default: [:]][sport, default: 0] += 1
        }
        return counts.mapValues { sportCounts in
            sportCounts.sorted { $0.value > $1.value }.map { $0.key.color }
        }
    }

    // MARK: - Actions

    private func shiftMonth(by delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private func pick(_ day: Date) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedDate = calendar.startOfDay(for: day)
        }
        onSelect()
    }
}
#endif
