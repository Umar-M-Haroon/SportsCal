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
    func makeUIView(context: Context) -> UICalendarView {
        let calendarView = UICalendarView()
        calendarView.calendar = Calendar.current
        calendarView.availableDateRange = DateInterval(start: viewModel.sortedGames.first?.key.date ?? .now, end: viewModel.sortedGames.last?.key.date ?? .now)
        calendarView.delegate = context.coordinator
        calendarView.locale = Locale.current
        calendarView.wantsDateDecorations = true
        calendarView.visibleDateComponents = Calendar.current.dateComponents([.day, .month, .year], from: .now)
        calendarView.fontDesign = .rounded
        return calendarView
    }
    
    func updateUIView(_ uiView: UICalendarView, context: Context) {
    }
    func makeCoordinator() -> CalendarCoordinator {
        CalendarCoordinator(model: viewModel)
    }
    
    typealias UIViewType = UICalendarView
    
}
@available(iOS 16.0, *)
class CalendarCoordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
    var model: GameViewModel
    
    init(model: GameViewModel) {
        self.model = model
    }
    
    func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
        
    }
    
    @MainActor func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
        guard let date = Calendar.current.date(from: dateComponents) else { return nil }
        let comps = Calendar.current.dateComponents([.day, .year, .month, .calendar], from: date)
        if let (_, games) = model.sortedGames.first(where: {$0.key == comps}) {
            let sports = games.compactMap { game -> SportType? in
                guard let league = game.idLeague,
                      let leagueInt = Int(league),
                      let foundLeague = Leagues(rawValue: leagueInt)
                      else {
                    return nil
                }
                return SportType(league: foundLeague)
            }
            
            return .customView {
//                let view = UIHostingController(rootView: DecorationView(showBasketball: sports.contains(.basketball), showSoccer: sports.contains(.soccer), showHockey: sports.contains(.hockey), showBaseball: sports.contains(.mlb), showFootball: sports.contains(.nfl))).view
                let view = UIHostingController(rootView: DecorationView(showBasketball: true, showSoccer: true, showHockey: true, showBaseball: true, showFootball: true)).view
                return view!
            }
        }
        return nil
    }
    
}

//struct CalendarViewRepresentable_Previews: PreviewProvider {
//    static var previews: some View {
//        CalendarViewRepresentable()
//    }
//}

