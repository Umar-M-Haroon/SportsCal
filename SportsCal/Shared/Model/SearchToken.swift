//
//  SearchToken.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/12/26.
//

import SwiftUI
import SportsCalModel

enum GameDay: String, Hashable {
    case today = "Today"
    case tomorrow = "Tomorrow"
}

enum SearchToken: Identifiable, Hashable {
    case sport(SportType)
    case live
    case favorites
    case team(String)
    case gameDay(GameDay)

    var id: String {
        switch self {
        case .sport(let sport): return "sport-\(sport.rawValue)"
        case .live: return "live"
        case .favorites: return "favorites"
        case .team(let name): return "team-\(name)"
        case .gameDay(let day): return "gameDay-\(day.rawValue)"
        }
    }

    @ViewBuilder
    var label: some View {
        switch self {
        case .sport(let sport):
            Label(sport.displayName, systemImage: sport.systemImage)
                .foregroundColor(sport.color)
        case .live:
            Label("Live", systemImage: "circle.fill")
                .foregroundColor(.red)
        case .favorites:
            Label("Favorites", systemImage: "star.fill")
                .foregroundColor(.yellow)
        case .team(let name):
            Label(name, systemImage: "person.fill")
        case .gameDay(let day):
            Label(day.rawValue, systemImage: "calendar")
        }
    }

    // MARK: - Suggestions

    static func suggestions(
        for searchText: String,
        currentTokens: [SearchToken],
        enabledSports: [SportType],
        favoriteTeams: Set<String>,
        hasLiveEvents: Bool
    ) -> [SearchToken] {
        var results: [SearchToken] = []

        if searchText.isEmpty {
            if hasLiveEvents {
                results.append(.live)
            }
            if !favoriteTeams.isEmpty {
                results.append(.favorites)
            }
            for sport in enabledSports {
                results.append(.sport(sport))
            }
            results.append(.gameDay(.today))
            results.append(.gameDay(.tomorrow))
        } else {
            let query = searchText.lowercased()

            for sport in enabledSports {
                if sport.capitalized.lowercased().contains(query) ||
                   sport.displayName.lowercased().contains(query) ||
                   sport.rawValue.lowercased().contains(query) {
                    results.append(.sport(sport))
                }
            }

            if hasLiveEvents && "live".contains(query) {
                results.append(.live)
            }

            if !favoriteTeams.isEmpty &&
               ("favorites".contains(query) || "starred".contains(query)) {
                results.append(.favorites)
            }

            if "today".contains(query) {
                results.append(.gameDay(.today))
            }
            if "tomorrow".contains(query) {
                results.append(.gameDay(.tomorrow))
            }

            for team in favoriteTeams.sorted() {
                if team.localizedCaseInsensitiveContains(searchText) {
                    results.append(.team(team))
                }
            }
        }

        results.removeAll { currentTokens.contains($0) }
        return results
    }

    // MARK: - Filtering

    static func filter(
        games: [GameWithTeams],
        tokens: [SearchToken],
        searchText: String,
        favorites: Favorites,
        liveGameIDs: Set<String>
    ) -> [GameWithTeams] {
        var result = games

        for token in tokens {
            switch token {
            case .sport(let sport):
                result = result.filter { $0.game.sportType == sport }
            case .live:
                result = result.filter { liveGameIDs.contains($0.game.id) }
            case .favorites:
                result = result.filter { favorites.contains($0.game) }
            case .team(let name):
                result = result.filter { matchesTeam($0, name: name) }
            case .gameDay(let day):
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let targetDate: Date
                switch day {
                case .today:
                    targetDate = today
                case .tomorrow:
                    targetDate = calendar.date(byAdding: .day, value: 1, to: today)!
                }
                let nextDay = calendar.date(byAdding: .day, value: 1, to: targetDate)!
                result = result.filter { gwt in
                    guard let gameDate = gwt.game.standardDate else { return false }
                    return gameDate >= targetDate && gameDate < nextDay
                }
            }
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter { matchesTeam($0, name: trimmed) }
        }

        return result
    }

    private static func matchesTeam(_ gwt: GameWithTeams, name: String) -> Bool {
        let game = gwt.game
        return game.strHomeTeam.localizedCaseInsensitiveContains(name) ||
               game.strAwayTeam.localizedCaseInsensitiveContains(name) ||
               (gwt.homeTeam?.strTeam ?? "").localizedCaseInsensitiveContains(name) ||
               (gwt.awayTeam?.strTeam ?? "").localizedCaseInsensitiveContains(name) ||
               (gwt.homeTeam?.strTeamShort ?? "").localizedCaseInsensitiveContains(name) ||
               (gwt.awayTeam?.strTeamShort ?? "").localizedCaseInsensitiveContains(name) ||
               (gwt.homeTeam?.strAlternate ?? "").localizedCaseInsensitiveContains(name) ||
               (gwt.awayTeam?.strAlternate ?? "").localizedCaseInsensitiveContains(name)
    }
}
