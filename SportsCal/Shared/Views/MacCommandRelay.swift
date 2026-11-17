//
//  MacCommandRelay.swift
//  SportsCal
//
//  Receives the menu-bar commands SportsCalApp posts through NotificationCenter
//  and forwards them to the window that applies it. Kept as a standalone
//  modifier so DayPage.body doesn't grow more inline .onReceive closures (its
//  modifier chain is already at the type-checker's edge).
//

#if os(macOS)
import SwiftUI

struct MacCommandRelay: ViewModifier {
    var onJumpToToday: () -> Void
    var onPreviousDay: () -> Void
    var onNextDay: () -> Void
    var onToggleInspector: () -> Void
    var onToggleFavoritesOnly: () -> Void
    var onPrint: () -> Void
    var onFocusSearch: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .jumpToToday)) { _ in
                onJumpToToday()
            }
            .onReceive(NotificationCenter.default.publisher(for: .previousDay)) { _ in
                onPreviousDay()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nextDay)) { _ in
                onNextDay()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
                onToggleInspector()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleFavoritesOnly)) { _ in
                onToggleFavoritesOnly()
            }
            .onReceive(NotificationCenter.default.publisher(for: .printSchedule)) { _ in
                onPrint()
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
                onFocusSearch()
            }
    }
}
#endif
