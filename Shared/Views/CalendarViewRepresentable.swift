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
        calendarView.availableDateRange = DateInterval(start: viewModel.totalGames?.first?.standardDate ?? .now, end: viewModel.totalGames?.last?.standardDate ?? .now)
        calendarView.delegate = context.coordinator
        calendarView.locale = Locale.current
        calendarView.wantsDateDecorations = true
        calendarView.visibleDateComponents = Calendar.current.dateComponents([.day, .month, .year], from: .now)
        calendarView.fontDesign = .rounded
        return calendarView
    }
    
    func updateUIView(_ uiView: UICalendarView, context: Context) {
        let componentsToReload = context.coordinator.reloadApplicableDecorations()
        uiView.reloadDecorations(forDateComponents: componentsToReload, animated: true)
    }
    func makeCoordinator() -> CalendarCoordinator {
        CalendarCoordinator(games: $viewModel.totalGames, date: $selectedDate, sheet: $sheetType, favorites: favorites.teams)
    }
    
    typealias UIViewType = UICalendarView
    
}
@available(iOS 16.0, *)
class CalendarCoordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
    
    @Binding var games: [Game]?
    @Binding var selectedDate: DateComponents?
    @Binding var sheetType: SheetType?
    var favorites: Set<String>
    
    init(games: Binding<[Game]?>, date: Binding<DateComponents?>, sheet: Binding<SheetType?>, favorites: Set<String>) {
        self._games = games
        self._selectedDate = date
        self._sheetType = sheet
        self.favorites = favorites
    }
    
    func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
        
    }
    
    @MainActor func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
        guard let date = Calendar.current.date(from: dateComponents) else { return nil }
        let comps = Calendar.current.dateComponents([.day, .year, .month, .calendar], from: date)
        
        if let filteredGames = games?.filter({$0.standardDate?.toComponents() == comps}) {
            let sports = filteredGames.compactMap { game -> SportType? in
                guard let league = game.idLeague,
                      let leagueInt = Int(league),
                      let foundLeague = Leagues(rawValue: leagueInt)
                      else {
                    return nil
                }
                return SportType(league: foundLeague)
            }
            
            return .customView {
//                let view = UIHostingController(rootView: DecorationView(showBasketball: sports.contains(.basketball), showSoccer: sports.contains(.soccer), showHockey: sports.contains(.hockey), showBaseball: sports.contains(.mlb), showFootball: sports.contains(.nfl), showFavorites: true)).view
                let view = UIHostingController(rootView: DecorationView(showBasketball: true, showSoccer: true, showHockey: true, showBaseball: true, showFootball: true, showFavorites: true)).view
                return view!
            }
        }
        return nil
    }
    func reloadApplicableDecorations() -> [DateComponents] {
        []
    }
}

//struct CalendarViewRepresentable_Previews: PreviewProvider {
//    static var previews: some View {
//        CalendarViewRepresentable()
//    }
//}

extension Date {
    func toComponents() -> DateComponents {
        Calendar.current.dateComponents([.day, .month, .year], from: self)
    }
}
