//
//  ModernDateScrubber.swift
//  SportsCal — Design System v1.0
//
//  Horizontal day-pill strip + chevron paging + Today reset, sized for the
//  macOS EFRemix layout. Uses design-system tokens (appSpace*, appInk*,
//  appAlt, appHeadline, appFootnote) so it sits cleanly between the sidebar
//  and the games grid.
//

import SwiftUI

struct ModernDateScrubber: View {
    @Binding var selectedDate: Date
    /// Optional set of date components (day/month/year) that have games. When
    /// non-nil, pills with games show a small dot underneath the day number.
    var datesWithGames: Set<DateComponents>? = nil
    var pastDays: Int = 7
    var futureDays: Int = 21

    private let calendar = Calendar.current

    @State private var scrollPosition: Date?

    var body: some View {
        HStack(spacing: .appSpace2) {
            chevron("chevron.left", offset: -1, accessibility: "Previous day")
            scrubberStrip
            chevron("chevron.right", offset: 1, accessibility: "Next day")
            todayButton
        }
        .padding(.horizontal, .appSpace3)
        .padding(.vertical, .appSpace2)
        .background(
            RoundedRectangle.appShape(.appRadiusSM)
                .fill(Color.appSurface)
        )
        .overlay(
            RoundedRectangle.appShape(.appRadiusSM)
                .stroke(Color.appDivider, lineWidth: 1)
        )
    }

    // MARK: - Pill strip

    private var scrubberStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.element.timeIntervalSince1970) { index, date in
                    if isNewMonth(date, previous: index > 0 ? days[index - 1] : nil) {
                        monthDivider(for: date)
                    }
                    pill(for: date)
                        .id(calendar.startOfDay(for: date))
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .onAppear {
            scrollPosition = calendar.startOfDay(for: selectedDate)
        }
        .onChange(of: selectedDate) { _, newValue in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                scrollPosition = calendar.startOfDay(for: newValue)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }

    private func pill(for date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let hasGames = hasGames(date)

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                selectedDate = calendar.startOfDay(for: date)
            }
        } label: {
            VStack(spacing: 1) {
                Text(weekdayText(for: date))
                    .font(.appFootnote)
                    .foregroundStyle(selected ? Color.appBackground : Color.appInkSoft)
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(.body, design: .rounded).weight(selected ? .bold : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.appBackground : Color.appInk)
                Circle()
                    .fill(dotColor(selected: selected, isToday: isToday, hasGames: hasGames))
                    .frame(width: 4, height: 4)
                    .opacity(isToday || hasGames ? 1 : 0)
            }
            .frame(width: 40, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.appInk : (isToday ? Color.appAlt : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .help(Self.fullDateFormatter.string(from: date))
        .accessibilityLabel(accessibilityLabel(for: date, isToday: isToday, hasGames: hasGames))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func monthDivider(for date: Date) -> some View {
        Text(Self.monthFormatter.string(from: date).uppercased())
            .font(.appFootnote)
            .foregroundStyle(Color.appInkFaint)
            .frame(width: 32, height: 48)
    }

    private func dotColor(selected: Bool, isToday: Bool, hasGames: Bool) -> Color {
        if selected { return Color.appBackground.opacity(0.7) }
        if isToday { return Color.appLive }
        if hasGames { return Color.appInkFaint }
        return .clear
    }

    // MARK: - Chevrons & Today

    private func chevron(_ systemName: String, offset: Int, accessibility: String) -> some View {
        Button {
            shiftBy(days: offset)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(Color.appInkSoft)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.appAlt.opacity(0.6))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .keyboardShortcut(offset < 0 ? .leftArrow : .rightArrow, modifiers: [])
    }

    private var todayButton: some View {
        let isOnToday = calendar.isDateInToday(selectedDate)
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                selectedDate = calendar.startOfDay(for: Date())
            }
        } label: {
            Text("Today")
                .font(.appFootnote)
                .foregroundStyle(isOnToday ? Color.appInkFaint : Color.appInk)
                .padding(.horizontal, .appSpace3)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOnToday ? Color.appAlt.opacity(0.4) : Color.appAlt)
                )
        }
        .buttonStyle(.plain)
        .disabled(isOnToday)
        .keyboardShortcut("t", modifiers: .command)
        .help("Jump to today (⌘T)")
    }

    // MARK: - Helpers

    private func shiftBy(days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            selectedDate = calendar.startOfDay(for: next)
        }
    }

    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (-pastDays...futureDays).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }
    }

    private func hasGames(_ date: Date) -> Bool {
        guard let dates = datesWithGames else { return false }
        let dc = calendar.dateComponents([.day, .month, .year], from: date)
        return dates.contains(dc)
    }

    private func isNewMonth(_ date: Date, previous: Date?) -> Bool {
        guard let previous else { return false }
        return calendar.component(.month, from: date) != calendar.component(.month, from: previous)
    }

    private func weekdayText(for date: Date) -> String {
        Self.weekdayFormatter.string(from: date).uppercased()
    }

    private func accessibilityLabel(for date: Date, isToday: Bool, hasGames: Bool) -> Text {
        var s = Self.fullDateFormatter.string(from: date)
        if isToday { s += ", today" }
        s += hasGames ? ", has games" : ", no games"
        return Text(s)
    }

    private static let weekdayFormatter: DateFormatter = {
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
}

#Preview {
    StatefulPreviewWrapper(Date()) { date in
        ModernDateScrubber(selectedDate: date)
            .padding()
            .frame(width: 720)
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}
