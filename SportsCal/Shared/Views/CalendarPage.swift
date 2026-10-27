//
//  CalendarPage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/9/26.
//

import SwiftUI
import SportsCalModel
import TipKit

#if os(iOS)
struct CalendarPage: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites
    @Binding var sheetType: SheetType?
    @Binding var showFavoritesOnly: Bool
    @Binding var spotlightDate: Date?
    @State private var navigateToDate: Date?
    @State private var sportFilter: SportChipFilter = .all
    @State private var showSportPicker: Bool = false
    @State private var browseSport: SportType?
    /// Width the page is laid out in: wide layouts show the day beside the month.
    @State private var layoutWidth: CGFloat = 0
    /// The day listed beside the calendar in wide layouts. Starts on today.
    @State private var inlineDay: DateComponents = Self.components(for: .now)
    /// The day opened in a sheet in compact layouts.
    @State private var sheetDay: SheetDay?
    /// Shown inline above the month rather than as popovers: on the iPhone Duo
    /// the toolbar is a side rail, and a popover anchored there covers the grid.
    @State private var calendarTips = TipGroup(.ordered) {
        SportFilterTip()
        CalendarFavoritesTip()
    }

    private struct SheetDay: Identifiable {
        let components: DateComponents
        var id: String { "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)" }
    }

    private var isWide: Bool {
        layoutWidth >= GamesLayout.splitMinWidth
    }

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: 0) {
                    monthColumn(selectedDay: inlineDay)
                        .frame(width: min(max(layoutWidth * 0.42, 360), 420))
                    Divider()
                    inlineDayColumn
                }
            } else {
                monthColumn(selectedDay: nil)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { layoutWidth = $0 }
        .conditionalModifier(
            storage.effectiveAppTheme == .ambient,
            ifTrue: { $0.background(AmbientPalette.bg.ignoresSafeArea()).preferredColorScheme(.dark) },
            ifFalse: { $0 }
        )
        .toolbar {
            ToolbarItem {
                sportFilterMenu
            }
        }
        // Scoped to the Calendar tab: presented from here, never from the root, and
        // only ever in response to a tap.
        .sheet(item: $sheetDay) { day in
            let games = dayGames(for: day.components)
            ListDetailView(listGames: games.listGames, liveGames: games.liveGames, sheetType: $sheetType)
                .environment(storage)
                .environment(viewModel)
                .environment(favorites)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSportPicker) {
            SportPickerSheet()
                .environment(storage)
                .environment(viewModel)
        }
        .sheet(item: $browseSport) { sport in
            SportBrowseSheet(sport: sport)
                .environment(viewModel)
                .environment(storage)
                .environment(favorites)
        }
        .onChange(of: storage.enabledSports) { oldValue, newValue in
            if case .sport(let sport) = sportFilter, !newValue.contains(sport) {
                sportFilter = .all
            }
        }
        .onChange(of: spotlightDate) { _, newDate in
            if let newDate {
                navigateToDate = newDate
                inlineDay = Self.components(for: newDate)
                spotlightDate = nil
            }
        }
    }

    // MARK: - Columns

    private func monthColumn(selectedDay: DateComponents?) -> some View {
        VStack(spacing: 0) {
            TipView(calendarTips.currentTip)
                .padding(.horizontal)
                .padding(.top, 8)
            CalendarViewRepresentable(
                showFavoritesOnly: $showFavoritesOnly,
                navigateToDate: $navigateToDate,
                sportFilter: $sportFilter,
                selectedDay: selectedDay,
                onSelectDay: openDay
            )
        }
    }

    /// The selected day's games, beside the month. Recomputed from the live view
    /// model, so scores tick here just as they do on the Games tab.
    private var inlineDayColumn: some View {
        let games = dayGames(for: inlineDay)
        return VStack(alignment: .leading, spacing: 0) {
            Text(Self.title(for: inlineDay))
                .font(.title3.weight(.semibold))
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ListDetailView(listGames: games.listGames, liveGames: games.liveGames, sheetType: $sheetType, isInline: true)
                .environment(storage)
                .environment(viewModel)
                .environment(favorites)
                .id(SheetDay(components: inlineDay).id)
        }
    }

    private func openDay(_ day: DateComponents) {
        if isWide {
            inlineDay = day
        } else {
            sheetDay = SheetDay(components: day)
        }
    }

    /// One day's games under the calendar's current filters.
    private func dayGames(for day: DateComponents) -> CalendarDayGames {
        var games = viewModel.calendarGames ?? []
        if showFavoritesOnly {
            games = games.filter { favorites.contains($0) }
        }
        games = games.filter { sportFilter.matches($0) }
        return CalendarDayGames(day: day, games: games, liveGames: viewModel.allLiveEvents)
    }

    private static func components(for date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: date)
    }

    private static func title(for day: DateComponents) -> String {
        guard let date = Calendar.current.date(from: day) else { return "" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: - Filter

    private var sportFilterIcon: String {
        switch sportFilter {
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .sport(let sport):
            return sport.systemImage
        }
    }

    @ViewBuilder
    private var sportFilterMenu: some View {
        let enabledSports = storage.enabledSports
        let disabledSports = storage.orderedSports.filter { !enabledSports.contains($0) }
        Menu {
            Picker("Filter", selection: $sportFilter) {
                Label("All Sports", systemImage: "square.grid.2x2")
                    .tag(SportChipFilter.all)
                ForEach(enabledSports, id: \.self) { sport in
                    let liveCount = viewModel.liveGameCountsBySport[sport] ?? 0
                    Label(liveCount > 0 ? "\(sport.capitalized) (\(liveCount) live)" : sport.capitalized,
                          systemImage: sport.systemImage)
                        .tag(SportChipFilter.sport(sport))
                }
            }
            .pickerStyle(.inline)

            if !disabledSports.isEmpty {
                Section("Browse") {
                    ForEach(disabledSports, id: \.self) { sport in
                        Button {
                            browseSport = sport
                        } label: {
                            Label(sport.capitalized, systemImage: sport.systemImage)
                        }
                    }
                }
            }

            Divider()
            Button {
                showSportPicker = true
            } label: {
                Label("Add Sports", systemImage: "plus")
            }
        } label: {
            Label("Filter", systemImage: sportFilterIcon)
                .symbolVariant(sportFilter == .all ? .none : .fill)
        }
    }
}
#endif

extension SportType: @retroactive Identifiable {
    public var id: String { rawValue }
}
