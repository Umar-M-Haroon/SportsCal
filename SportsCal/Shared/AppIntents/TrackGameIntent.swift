//
//  TrackGameIntent.swift
//  SportsCal
//
//  Siri: "Start tracking the Lakers game in SportsCal"
//  Adds the matching game to auto-follow so a Live Activity starts when it goes live.
//

import AppIntents
import SportsCalModel

struct TeamQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TeamEntity] {
        identifiers.map { TeamEntity(id: $0, name: $0) }
    }

    func suggestedEntities() async throws -> [TeamEntity] {
        let favorites = IntentDataProvider.readFavorites()
        let allNames = IntentDataProvider.allTeamNames()
        // Show favorites first, then others
        let sorted = allNames.sorted { lhs, rhs in
            let lhsFav = favorites.contains(lhs)
            let rhsFav = favorites.contains(rhs)
            if lhsFav != rhsFav { return lhsFav }
            return lhs < rhs
        }
        return sorted.map { TeamEntity(id: $0, name: $0) }
    }
}

struct TeamEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Team"
    static var defaultQuery = TeamQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct TrackGameIntent: AppIntent {
    static var title: LocalizedStringResource = "Track Game"
    static var description: IntentDescription = "Start tracking a team's game with a Live Activity when it begins."

    @Parameter(title: "Team")
    var team: TeamEntity

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let games = IntentDataProvider.readCachedGames()
        let teamName = team.name

        guard let game = games.first(where: { $0.strHomeTeam == teamName || $0.strAwayTeam == teamName }),
              let eventID = game.idEvent else {
            return .result(dialog: "Couldn't find an upcoming game for \(teamName).")
        }

        // Write to auto-follow IDs in app group
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        var ids = defaults?.stringArray(forKey: "autoFollowEventIDs") ?? []
        if !ids.contains(eventID) {
            ids.append(eventID)
            defaults?.set(ids, forKey: "autoFollowEventIDs")
        }

        return .result(dialog: "Tracking \(game.strAwayTeam) at \(game.strHomeTeam). You'll get a Live Activity when the game starts.")
    }
}
