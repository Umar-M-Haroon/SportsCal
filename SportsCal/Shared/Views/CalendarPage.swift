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

    var body: some View {
        CalendarViewRepresentable(
            sheetType: $sheetType,
            showFavoritesOnly: $showFavoritesOnly,
            navigateToDate: $navigateToDate,
            sportFilter: $sportFilter
        )
        .conditionalModifier(
            storage.appTheme == .ambient,
            ifTrue: { $0.background(AmbientPalette.bg.ignoresSafeArea()).preferredColorScheme(.dark) },
            ifFalse: { $0 }
        )
        .toolbar {
            ToolbarItem {
                sportFilterMenu
            }
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
                spotlightDate = nil
            }
        }
    }

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
            Image(systemName: sportFilterIcon)
                .symbolVariant(sportFilter == .all ? .none : .fill)
        }
        .popoverTip(SportFilterTip())
    }
}
#endif

extension SportType: @retroactive Identifiable {
    public var id: String { rawValue }
}
