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
    /// Half-window rendered on each side of the *selected* day. The window is
    /// anchored on `selectedDate`, so paging past the edge re-centers it —
    /// there is no fixed limit on how far back or forward you can travel.
    var pastDays: Int = 60
    var futureDays: Int = 60
    private let calendar = Calendar.current
    @State private var showDatePicker = false

    private static let dayAbbreviationFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var days: [Date] {
        // Anchor the window on the selected day so it follows the user as they
        // page — no fixed floor or ceiling on how far they can travel.
        let anchor = calendar.startOfDay(for: selectedDate)
        return (-pastDays...futureDays).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: anchor)
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
        return datesWithGames.contains(dc)
    }

    private func isNewMonth(_ date: Date, previousDate: Date?) -> Bool {
        guard let prev = previousDate else { return false }
        return calendar.component(.month, from: date) != calendar.component(.month, from: prev)
    }

    @State private var scrollPosition: Date?

    var body: some View {
        HStack(spacing: 8) {
            strip
            if !isToday(selectedDate) {
                todayButton
            }
            datePickerButton
        }
        // A horizontal ScrollView is greedy vertically; pin the whole strip to a
        // compact height so it stays a thin bar at the top instead of expanding
        // to fill the pane and pushing the board down.
        .frame(height: 60)
        .sensoryFeedback(.selection, trigger: selectedDate)
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                scrollPosition = calendar.startOfDay(for: newValue)
            }
        }
    }

    private var todayButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedDate = today
            }
        } label: {
            Text("Today")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .help("Jump to today")
    }

    private var datePickerButton: some View {
        Button {
            showDatePicker.toggle()
        } label: {
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Jump to date…")
        .accessibilityLabel("Jump to date")
        .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
            DatePicker(
                "Jump to date",
                selection: Binding(
                    get: { selectedDate },
                    set: { newValue in
                        selectedDate = calendar.startOfDay(for: newValue)
                        showDatePicker = false
                    }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding()
            .frame(minWidth: 300)
        }
    }

    private func monthDivider(for date: Date) -> some View {
        return Text(Self.monthFormatter.string(from: date).uppercased())
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
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
        .accessibilityLabel(chipAccessibilityLabel(for: date, isToday: today, hasGames: hasGames))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chipAccessibilityLabel(for date: Date, isToday: Bool, hasGames: Bool) -> Text {
        let fullDate = Self.fullDateFormatter.string(from: date)
        var parts = fullDate
        if isToday {
            parts += ", today"
        }
        if hasGames {
            parts += ", has games"
        } else {
            parts += ", no games"
        }
        return Text(parts)
    }

    private func dayAbbreviation(for date: Date) -> String {
        Self.dayAbbreviationFormatter.string(from: date).prefix(3).uppercased()
    }
}
