//
//  SportsCalShortcuts.swift
//  SportsCal
//
//  Registers App Shortcuts for Siri and the Shortcuts app.
//  These are also available to Apple Intelligence for natural language mapping.
//

import AppIntents

struct SportsCalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowFavoriteGamesIntent(),
            phrases: [
                "Show my favorite games in \(.applicationName)",
                "Show my favorites in \(.applicationName)",
                "Open my favorite teams in \(.applicationName)"
            ],
            shortTitle: "Favorite Games",
            systemImageName: "star.fill"
        )

        AppShortcut(
            intent: TrackGameIntent(),
            phrases: [
                "Track the \(\.$team) game in \(.applicationName)",
                "Start tracking \(\.$team) in \(.applicationName)",
                "Follow the \(\.$team) game in \(.applicationName)"
            ],
            shortTitle: "Track Game",
            systemImageName: "dot.radiowaves.left.and.right"
        )

        AppShortcut(
            intent: AddFavoriteTeamIntent(),
            phrases: [
                "Add \(\.$team) to my favorites in \(.applicationName)",
                "Favorite \(\.$team) in \(.applicationName)"
            ],
            shortTitle: "Add Favorite",
            systemImageName: "star"
        )

        AppShortcut(
            intent: OpenSportIntent(),
            phrases: [
                "Open \(\.$sport) games in \(.applicationName)",
                "Show \(\.$sport) in \(.applicationName)"
            ],
            shortTitle: "Open Sport",
            systemImageName: "sportscourt"
        )
    }
}
