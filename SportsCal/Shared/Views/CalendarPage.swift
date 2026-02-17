//
//  CalendarPage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/9/26.
//

import SwiftUI
import SportsCalModel

#if os(iOS)
struct CalendarPage: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites
    @Binding var sheetType: SheetType?
    @Binding var showFavoritesOnly: Bool
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
        .safeAreaInset(edge: .top, spacing: 0) {
            SportChipFilterView(selectedFilter: $sportFilter, showSportPicker: $showSportPicker, browseSport: $browseSport)
                .environment(storage)
                .environment(viewModel)
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
    }
}
#endif

extension SportType: @retroactive Identifiable {
    public var id: String { rawValue }
}
