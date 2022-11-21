//
//  CalendarButton.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/27/22.
//

import SwiftUI
import EventKitUI
import SportsCalModel

struct CalendarButton: View {
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var game: Game
    var body: some View {
        Button {
            if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                shouldShowSportsCalProAlert = true
            } else {
                EKEventStore().requestAccess(to: .event) { success, err in
                    print("⚠️changing sheet type to a calendar with game \(game)")
                    sheetType = .calendar(game: game)
                }
            }
        } label: {
            Label("Add to Calendar", systemImage: "calendar")
        }
    }
}
//
//struct CalendarButton_Previews: PreviewProvider {
//    static var previews: some View {
//        CalendarButton(shouldShowSportsCalProAlert: <#Binding<Bool>#>, sheetType: <#Binding<SheetType>#>, game: <#Game#>)
//    }
//}
