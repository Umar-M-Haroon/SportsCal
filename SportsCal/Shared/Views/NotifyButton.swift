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
    /// Race weekends: `EventSession.reminderKey`s with a pending per-session reminder.
    @State private var scheduledSessions: Set<String> = []

    /// Race weekends' other sessions still to come (Quali, Sprint…); the duration
    /// options above them time to the headline session (the Race).
    private var extraSessions: [EventSession] {
        guard game.isRace else { return [] }
        let headlineKey = game.headlineSession?.reminderKey
        return game.upcomingSessions().filter { $0.reminderKey != headlineKey }
    }

    var body: some View {
        Menu {
            // Game Starting Now option
            Button {
                scheduleNotification(duration: .gameStarting)
            } label: {
                HStack {
                    Text(game.isRace ? "When the \((game.headlineSession?.shortName ?? "race").lowercased()) starts" : "When game starts")
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

            if !extraSessions.isEmpty {
                Section("Other sessions") {
                    ForEach(extraSessions, id: \.reminderKey) { session in
                        Button {
                            toggleSessionReminder(session)
                        } label: {
                            HStack {
                                Text(sessionLabel(session))
                                if scheduledSessions.contains(session.reminderKey) {
                                    Image(systemName: "checkmark")
                                } else if isGated(.gameStarting) {
                                    Image(systemName: "lock.fill")
                                }
                            }
                        }
                    }
                }
            }

            Divider()

            // Cancel all notifications
            if !scheduledNotifications.isEmpty || !scheduledSessions.isEmpty {
                Button(role: .destructive) {
                    cancelAllNotifications()
                } label: {
                    Label("Cancel All Reminders", systemImage: "bell.slash")
                }
            }
        } label: {
            let isNotifying = !scheduledNotifications.isEmpty || !scheduledSessions.isEmpty
            Label(isNotifying ? "Notifying" : "Notify Me", systemImage: isNotifying ? "bell.badge.fill" : "bell.badge")
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
        // A race weekend's own date is FP1: time the reminder to its Race.
        guard let gameDate = game.headlineSession?.startDate ?? game.standardDate else { return }

        NotificationManager.addLocalNotification(date: gameDate, item: game, duration: duration)
        scheduledNotifications.insert(duration)
        MonetizationTelemetry.firstReminderSet()
        // Spend a free allowance slot for a brand-new game-start reminder.
        if duration == .gameStarting, !subscriptionManager.isPro, let favKey = favoriteTeamKey {
            storage.recordFreeReminderTeam(favKey)
        }
    }

    /// "Qualifying · Sat 3:00 PM".
    private func sessionLabel(_ session: EventSession) -> String {
        guard let start = session.startDate else { return session.displayName }
        return "\(session.displayName) · \(start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }

    /// One "starting now" reminder per extra session; gated like a game-start reminder.
    private func toggleSessionReminder(_ session: EventSession) {
        guard let gameID = game.idEvent else { return }
        let key = session.reminderKey
        if scheduledSessions.contains(key) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [NotificationManager.sessionIdentifier(gameID: gameID, session: session)])
            scheduledSessions.remove(key)
            return
        }
        let decision = gateDecision(for: .gameStarting)
        guard decision.isAllowed else {
            if let feature = decision.blockedFeature {
                MonetizationTelemetry.gateHit(feature)
            }
            UpsellCoordinator.shared.request(.freeReminderCapHit) {
                shouldShowSportsCalProAlert = true
            }
            return
        }
        guard let start = session.startDate else { return }
        NotificationManager.addLocalNotification(date: start, item: game, duration: .gameStarting, session: session)
        scheduledSessions.insert(key)
    }

    private func cancelAllNotifications() {
        if let gameID = game.idEvent {
            NotificationManager.cancelNotifications(for: gameID)
            scheduledNotifications.removeAll()
            scheduledSessions.removeAll()
            if !subscriptionManager.isPro, let favKey = favoriteTeamKey {
                storage.releaseFreeReminderTeam(favKey)
            }
        }
    }

    private func checkScheduledNotifications() {
        guard let gameID = game.idEvent else { return }
        if game.isRace {
            NotificationManager.scheduledSessionKeys(for: gameID) { keys in
                DispatchQueue.main.async { scheduledSessions = keys }
            }
        }
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
