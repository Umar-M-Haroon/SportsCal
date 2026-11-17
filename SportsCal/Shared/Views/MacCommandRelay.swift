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

    // Every open window gets these posts; only the frontmost one acts, or ⌘P would
    // print once per window and two windows would flip favorites-only back.
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .jumpToToday)) { _ in
                if appearsActive { onJumpToToday() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .previousDay)) { _ in
                if appearsActive { onPreviousDay() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .nextDay)) { _ in
                if appearsActive { onNextDay() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
                if appearsActive { onToggleInspector() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleFavoritesOnly)) { _ in
                if appearsActive { onToggleFavoritesOnly() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .printSchedule)) { _ in
                if appearsActive { onPrint() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
                if appearsActive { onFocusSearch() }
            }
    }
}
#endif
