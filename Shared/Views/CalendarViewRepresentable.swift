//
//  CalendarViewRepresentable.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/15/23.
//

import SwiftUI
import SportsCalModel
import UIKit

@available(iOS 16.0, *)
struct CalendarViewRepresentable: UIViewRepresentable {
    @EnvironmentObject var viewModel: GameViewModel
    @EnvironmentObject var favorites: Favorites
    @State var selectedDate: DateComponents? = nil
    @Binding var sheetType: SheetType?
    func makeUIView(context: Context) -> UICalendarView {
        let calendarView = UICalendarView()
        calendarView.calendar = Calendar.current
        calendarView.selectionBehavior = UICalendarSelectionSingleDate(delegate: context.coordinator)
//        calendarView.availableDateRange = DateInterval(start: viewModel.totalGames?.first?.standardDate ?? .now, end: viewModel.totalGames?.last?.standardDate ?? .now)
        calendarView.delegate = context.coordinator
        calendarView.locale = Locale.current
        calendarView.wantsDateDecorations = true
        calendarView.visibleDateComponents = Calendar.current.dateComponents([.day, .month, .year], from: .now)
        calendarView.fontDesign = .rounded
        return calendarView
    }
    
    func updateUIView(_ uiView: UICalendarView, context: Context) {
        let componentsToReload = context.coordinator.reloadApplicableDecorations()
        print("RELOADING CALENDAR")
        let newGames = Dictionary(grouping: viewModel.totalGames ?? [], by: { game in
            game.standardDate?.toComponents()
        })
        var newLiveGames = Dictionary(grouping: viewModel.liveEvents, by: { game in
            game.standardDate?.toComponents()
        })
        context.coordinator.games = newGames
        context.coordinator.liveGames = newLiveGames
        if let selectedDate {
            context.coordinator.presentSheetForSelectedDate(dateComponents: selectedDate)
        }
        uiView.reloadDecorations(forDateComponents: componentsToReload, animated: true)
    }
    func makeCoordinator() -> CalendarCoordinator {
        let groupedGames = Dictionary(grouping: viewModel.totalGames ?? [], by: { game in
            game.standardDate?.toComponents()
        })
        var groupedLiveGames = Dictionary(grouping: viewModel.liveEvents, by: { game in
            game.standardDate?.toComponents()
        })
        return CalendarCoordinator(games: groupedGames, liveGames: groupedLiveGames, date: $selectedDate, sheet: $sheetType, favorites: favorites.teams)
    }
    
    typealias UIViewType = UICalendarView
    
}
@available(iOS 16.0, *)
class CalendarCoordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
    
    var games: [DateComponents? : [Game]]
    var liveGames: [DateComponents? : [Game]]
    @Binding var selectedDate: DateComponents?
    @Binding var sheetType: SheetType?
    var favorites: Set<String>
    
    init(games: [DateComponents? : [Game]], liveGames: [DateComponents? : [Game]], date: Binding<DateComponents?>, sheet: Binding<SheetType?>, favorites: Set<String>) {
        self.games = games
        self._selectedDate = date
        self._sheetType = sheet
        self.favorites = favorites
        self.liveGames = liveGames
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
            var newDict: [DateComponents: [Game]] = [:]
            for sort in sorted {
                newDict[sort.key] = sort.value
            }
            listSorted = sorted
        }
        
        sheetType = .listDetail(games: listSorted, liveGames: liveSorted)
    }
    
    @MainActor func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
        guard let date = Calendar.current.date(from: dateComponents) else { return nil }
        let comps = Calendar.current.dateComponents([.day, .year, .month, .calendar], from: date)
        
        
        if let filteredGames = games[comps] {
            let sports = filteredGames.compactMap { game -> SportType? in
                guard let league = game.idLeague,
                      let leagueInt = Int(league),
                      let foundLeague = Leagues(rawValue: leagueInt)
                      else {
                    return nil
                }
                return SportType(league: foundLeague)
            }
            if sports.isEmpty {
                return nil
            }
            let showFavorites = filteredGames.contains(where: {favorites.contains($0.strAwayTeam) || favorites.contains($0.strHomeTeam)})
            
            return .customView {
                let view = UIHostingController(rootView: DecorationView(showBasketball: sports.contains(.basketball), showSoccer: sports.contains(.soccer), showHockey: sports.contains(.hockey), showBaseball: sports.contains(.mlb), showFootball: sports.contains(.basketball), showFavorites: showFavorites)).view
//                let view = UIHostingController(rootView: DecorationView(showBasketball: true, showSoccer: true, showHockey: true, showBaseball: true, showFootball: true, showFavorites: true)).view
                return view!
            }
        } else {
            print("no filtered games")
        }
        return nil
    }
    func reloadApplicableDecorations() -> [DateComponents] {
        if let selectedDate {
            return [Date.now.toComponents(), selectedDate]
        }
        return [Date.now.toComponents()]
    }
}

//struct CalendarViewRepresentable_Previews: PreviewProvider {
//    static var previews: some View {
//        CalendarViewRepresentable()
//    }
//}

extension Date {
    func toComponents() -> DateComponents {
        Calendar.current.dateComponents([.day, .month, .year, .calendar], from: self)
    }
}
