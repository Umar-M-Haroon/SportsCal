//
//  PushToStartRegistrationPlanner.swift
//  SportsCal
//
//  Created by Umar Haroon on 2026-06-09.
//

import Foundation

/// What a push-to-start registration will send to the server.
struct PushToStartPayload: Equatable {
    var favorites: [String]
    var eventIDs: [String]
}

/// Pure decision logic for push-to-start registration, shared by every
/// registration call site in GameViewModel so the guard ("is there anything
/// to register?") and the favorites-toggle suppression can't drift apart.
enum PushToStartRegistrationPlanner {
    /// Returns nil when there is nothing to register: no auto-followed events
    /// and either no favorites or the auto-follow-favorites toggle is off.
    /// Favorites are included only while the toggle is on. Arrays are sorted
    /// so repeated registrations with the same state send identical payloads.
    static func payload(
        autoFollowFavorites: Bool,
        favoriteTeams: Set<String>,
        autoFollowEventIDs: Set<String>
    ) -> PushToStartPayload? {
        let hasFavorites = autoFollowFavorites && !favoriteTeams.isEmpty
        let hasAutoFollows = !autoFollowEventIDs.isEmpty
        guard hasFavorites || hasAutoFollows else { return nil }
        return PushToStartPayload(
            favorites: autoFollowFavorites ? favoriteTeams.sorted() : [],
            eventIDs: autoFollowEventIDs.sorted()
        )
    }
}
