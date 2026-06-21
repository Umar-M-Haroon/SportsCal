//
//  NotifyButton.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/27/22.
//

import SwiftUI
#if os(iOS)
import EventKitUI
#endif
import SportsCalModel
import UserNotifications

struct NotifyButton: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(Favorites.self) private var favorites
    @Environment(UserDefaultStorage.self) private var storage
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var game: Game
    @State private var scheduledNotifications: Set<NotificationDuration> = []

    var body: some View {
        Menu {
            // Game Starting Now option
            Button {
                scheduleNotification(duration: .gameStarting)
            } label: {
                HStack {
                    Text("When game starts")
                    if scheduledNotifications.contains(.gameStarting) {
                        Image(systemName: "checkmark")
                    } else if isGated(.gameStarting) {
                        Image(systemName: "lock.fill")
                    }
                }
            }

            Divider()

            // 30 minutes before
            Button {
                scheduleNotification(duration: .thirtyMinutes)
            } label: {
                HStack {
                    Text("\(NotificationDuration.thirtyMinutes.rawValue) before")
                    if scheduledNotifications.contains(.thirtyMinutes) {
                        Image(systemName: "checkmark")
                    } else if isGated(.thirtyMinutes) {
                        Image(systemName: "lock.fill")
                    }
                }
            }

            // 1 hour before
            Button {
                scheduleNotification(duration: .oneHour)
            } label: {
                HStack {
                    Text("\(NotificationDuration.oneHour.rawValue) before")
                    if scheduledNotifications.contains(.oneHour) {
                        Image(systemName: "checkmark")
                    } else if isGated(.oneHour) {
                        Image(systemName: "lock.fill")
                    }
                }
            }

            // 2 hours before
            Button {
                scheduleNotification(duration: .twoHour)
            } label: {
                HStack {
                    Text("\(NotificationDuration.twoHour.rawValue) before")
                    if scheduledNotifications.contains(.twoHour) {
                        Image(systemName: "checkmark")
                    } else if isGated(.twoHour) {
                        Image(systemName: "lock.fill")
                    }
                }
            }

            Divider()

            // Cancel all notifications
            if !scheduledNotifications.isEmpty {
                Button(role: .destructive) {
                    cancelAllNotifications()
                } label: {
                    Label("Cancel All Reminders", systemImage: "bell.slash")
                }
            }
        } label: {
            Label(scheduledNotifications.isEmpty ? "Notify Me" : "Notifying", systemImage: scheduledNotifications.isEmpty ? "bell.badge" : "bell.badge.fill")
        }
        .onAppear {
            checkScheduledNotifications()
        }
    }

    /// Identifier of the favorited team this game features (home preferred),
    /// or nil if neither side is a favorite. Used to apply the free game-start
    /// reminder allowance per-team. Falls back to team names for legacy/unresolved
    /// favorites.
    private var favoriteTeamKey: String? {
        if let homeID = game.idHomeTeam, !homeID.isEmpty, favorites.teamIDs.contains(homeID) { return homeID }
        if let awayID = game.idAwayTeam, !awayID.isEmpty, favorites.teamIDs.contains(awayID) { return awayID }
        if favorites.contains(game.strHomeTeam) { return game.strHomeTeam }
        if favorites.contains(game.strAwayTeam) { return game.strAwayTeam }
        return nil
    }

    /// Evaluate the free→Pro ladder for a given reminder duration.
    private func gateDecision(for duration: NotificationDuration) -> GateDecision {
        let kind: ReminderKind = (duration == .gameStarting) ? .gameStart : .preGame
        let favKey = favoriteTeamKey
        return NotificationGate.decision(
            isPro: subscriptionManager.isPro,
            kind: kind,
            gameInvolvesFavorite: favKey != nil,
            distinctFreeReminderTeams: storage.freeReminderTeamCount,
            teamAlreadyCounted: favKey.map { storage.isFreeReminderTeamCounted($0) } ?? false
        )
    }

    /// True when the duration would be blocked behind Pro for the current user —
    /// drives the lock badge in the menu.
    private func isGated(_ duration: NotificationDuration) -> Bool {
        !gateDecision(for: duration).isAllowed
    }

    private func scheduleNotification(duration: NotificationDuration) {
        // Cancelling an already-scheduled reminder is always allowed.
        if scheduledNotifications.contains(duration) {
            if let gameID = game.idEvent {
                let notiCenter = UNUserNotificationCenter.current()
                notiCenter.removePendingNotificationRequests(withIdentifiers: ["\(gameID)_\(duration.rawValue)"])
                scheduledNotifications.remove(duration)
                // Release the free allowance slot when the last game-start reminder
                // for this favorite team is removed (best-effort: another followed
                // game for the same team may still hold it, which only ever frees
                // the slot too early — never blocks unfairly).
                if duration == .gameStarting, !subscriptionManager.isPro, let favKey = favoriteTeamKey {
                    storage.releaseFreeReminderTeam(favKey)
                }
            }
            return
        }

        // Scheduling a new reminder runs the free→Pro ladder.
        let decision = gateDecision(for: duration)
        guard decision.isAllowed else {
            if let feature = decision.blockedFeature {
                MonetizationTelemetry.gateHit(feature)
            }
            // Route through the coordinator so the prompt is throttled + tracked.
            UpsellCoordinator.shared.request(.freeReminderCapHit) {
                shouldShowSportsCalProAlert = true
            }
            return
        }
        guard let gameDate = game.standardDate else { return }

        NotificationManager.addLocalNotification(date: gameDate, item: game, duration: duration)
        scheduledNotifications.insert(duration)
        // Spend a free allowance slot for a brand-new game-start reminder.
        if duration == .gameStarting, !subscriptionManager.isPro, let favKey = favoriteTeamKey {
            storage.recordFreeReminderTeam(favKey)
        }
    }

    private func cancelAllNotifications() {
        if let gameID = game.idEvent {
            NotificationManager.cancelNotifications(for: gameID)
            scheduledNotifications.removeAll()
            if !subscriptionManager.isPro, let favKey = favoriteTeamKey {
                storage.releaseFreeReminderTeam(favKey)
            }
        }
    }

    private func checkScheduledNotifications() {
        guard let gameID = game.idEvent else { return }
        for duration in NotificationDuration.allCases {
            NotificationManager.isNotificationScheduled(for: gameID, duration: duration) { isScheduled in
                DispatchQueue.main.async {
                    if isScheduled {
                        scheduledNotifications.insert(duration)
                    }
                }
            }
        }
    }
}

#Preview {
    NotifyButton(shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), game: Game(idLeague: "4387", strHomeTeam: "Lakers", strAwayTeam: "Celtics", isoDate: nil))
        .environment(SubscriptionManager.shared)
        .environment(Favorites())
        .environment(UserDefaultStorage())
}
