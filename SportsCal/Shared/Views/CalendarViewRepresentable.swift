//
//  CalendarViewRepresentable.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/15/23.
//

#if os(iOS)
import SwiftUI
import SportsCalModel
import UIKit

struct CalendarViewRepresentable: UIViewRepresentable {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @Environment(UserDefaultStorage.self) private var storage
    @State var selectedDate: DateComponents? = nil
    @Binding var sheetType: SheetType?
    @Binding var showFavoritesOnly: Bool
    @Binding var navigateToDate: Date?
    @Binding var sportFilter: SportChipFilter

    func makeUIView(context: Context) -> UICalendarView {
        let calendarView = UICalendarView()
        calendarView.calendar = Calendar.current
        calendarView.selectionBehavior = UICalendarSelectionSingleDate(delegate: context.coordinator)
        calendarView.delegate = context.coordinator
        calendarView.locale = Locale.current
        calendarView.wantsDateDecorations = true
        calendarView.visibleDateComponents = Calendar.current.dateComponents([.day, .month, .year], from: .now)
        calendarView.fontDesign = .rounded
        return calendarView
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        var gamesToUse = viewModel.calendarGames ?? []
        if showFavoritesOnly {
            gamesToUse = gamesToUse.filter { favorites.contains($0) }
        }
        gamesToUse = gamesToUse.filter { sportFilter.matches($0) }
        let newGames = Dictionary(grouping: gamesToUse, by: { game in
            game.standardDate?.toComponents()
        })
        let newLiveGames = Dictionary(grouping: viewModel.allLiveEvents, by: { game in
            game.standardDate?.toComponents()
        })

        let newDateSet = Set(newGames.keys.compactMap { $0 })
        let componentsToReload = context.coordinator.reloadApplicableDecorations(newDates: newDateSet)

        context.coordinator.games = newGames
        context.coordinator.liveGames = newLiveGames
        context.coordinator.favorites = favorites.teams
        context.coordinator.showFavoritesOnly = showFavoritesOnly
        if let selectedDate {
            context.coordinator.presentSheetForSelectedDate(dateComponents: selectedDate)
        }
        if let navigateToDate {
            uiView.visibleDateComponents = Calendar.current.dateComponents([.day, .month, .year], from: navigateToDate)
            DispatchQueue.main.async { self.navigateToDate = nil }
        }
        uiView.reloadDecorations(forDateComponents: componentsToReload, animated: true)
    }

    func makeCoordinator() -> CalendarCoordinator {
        let filteredCalendarGames = (viewModel.calendarGames ?? []).filter { sportFilter.matches($0) }
        let groupedGames = Dictionary(grouping: filteredCalendarGames, by: { game in
            game.standardDate?.toComponents()
        })
        let groupedLiveGames = Dictionary(grouping: viewModel.allLiveEvents, by: { game in
            game.standardDate?.toComponents()
        })
        return CalendarCoordinator(games: groupedGames, liveGames: groupedLiveGames, date: $selectedDate, sheet: $sheetType, favorites: favorites.teams, showFavoritesOnly: showFavoritesOnly)
    }

    typealias UIViewType = UICalendarView

}

class CalendarCoordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {

    var games: [DateComponents? : [Game]]
    var liveGames: [DateComponents? : [Game]]
    @Binding var selectedDate: DateComponents?
    @Binding var sheetType: SheetType?
    var favorites: Set<String>
    var showFavoritesOnly: Bool
    var previousGameDates: Set<DateComponents> = []

    init(games: [DateComponents? : [Game]], liveGames: [DateComponents? : [Game]], date: Binding<DateComponents?>, sheet: Binding<SheetType?>, favorites: Set<String>, showFavoritesOnly: Bool) {
        self.games = games
        self._selectedDate = date
        self._sheetType = sheet
        self.favorites = favorites
        self.liveGames = liveGames
        self.showFavoritesOnly = showFavoritesOnly
    }

    func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
        selectedDate = dateComponents
        presentSheetForSelectedDate(dateComponents: dateComponents)
    }

    func presentSheetForSelectedDate(dateComponents: DateComponents?) {
        guard let dateComponents,
              let date = Calendar.current.date(from: dateComponents) else { return }
        let comps = Calendar.current.dateComponents([.day, .year, .month, .calendar], from: date)
        var liveSorted: [Game] = []
        var listSorted: [Dictionary<DateComponents, [Game]>.Element] = []
        if let liveGames = liveGames[comps] {
            liveSorted = liveGames
        }
        if let listGames = games[comps] {
            let groupDic = Dictionary(grouping: listGames) { game -> DateComponents in
                let gameDate = game.standardDate ?? .now
                let date2 = Calendar.current.dateComponents([.day, .year, .month, .calendar], from: gameDate)
                return date2
            }
            let sorted = groupDic.sorted(by: {
                return $0.key.date! < $1.key.date!
            })
            listSorted = sorted
        }

        sheetType = .listDetail(games: listSorted, liveGames: liveSorted)
    }

    @MainActor func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
        guard let date = Calendar.current.date(from: dateComponents) else { return nil }
        let comps = Calendar.current.dateComponents([.day, .year, .month, .calendar], from: date)

        if let filteredGames = games[comps] {
            let sportTypes = Set(filteredGames.compactMap { game -> SportType? in
                guard let league = game.idLeague,
                      let leagueInt = Int(league),
                      let foundLeague = Leagues(rawValue: leagueInt)
                      else {
                    return nil
                }
                return SportType(league: foundLeague)
            })
            if sportTypes.isEmpty {
                return nil
            }
            let showFavorites = filteredGames.contains(where: { favorites.contains($0.strAwayTeam) || favorites.contains($0.strHomeTeam) })

            return .customView {
                let view = UIHostingController(rootView: DecorationView(sportTypes: sportTypes, gameCount: filteredGames.count, showFavorites: showFavorites)).view
                return view!
            }
        }
        return nil
    }

    func reloadApplicableDecorations(newDates: Set<DateComponents>) -> [DateComponents] {
        let allDates = previousGameDates.union(newDates)
        previousGameDates = newDates
        var result = Array(allDates)
        result.append(Date.now.toComponents())
        if let selectedDate {
            result.append(selectedDate)
        }
        return result
    }
}

extension Date {
    func toComponents() -> DateComponents {
        Calendar.current.dateComponents([.day, .month, .year, .calendar], from: self)
    }
}
#endif
