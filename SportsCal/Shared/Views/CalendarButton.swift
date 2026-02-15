//
//  CalendarButton.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/27/22.
//

import SwiftUI
import SportsCalModel
import os

#if os(iOS)
import EventKitUI

struct CalendarButton: View {
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var game: Game
    var body: some View {
        Button {
                EKEventStore().requestAccess(to: .event) { success, err in
                    AppLogger.calendar.info("Changing sheet type to calendar with game \(game.strAwayTeam) @ \(game.strHomeTeam)")
                    sheetType = .calendar(game: game)
                }
        } label: {
            Label("Add to Calendar", systemImage: "calendar")
        }
    }
}
#else
struct CalendarButton: View {
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var game: Game
    var body: some View {
        EmptyView()
    }
}
#endif
