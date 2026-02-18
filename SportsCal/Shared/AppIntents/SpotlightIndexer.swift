//
//  SpotlightIndexer.swift
//  SportsCal
//
//  Indexes games and favorite teams in CoreSpotlight for system-wide search.
//

import CoreSpotlight
import SportsCalModel
import os

enum SpotlightIndexer {
    private static let domainGames = "com.sportscal.games"
    private static let domainTeams = "com.sportscal.teams"

    /// Indexes upcoming games in CoreSpotlight.
    /// Call after schedule data refreshes or sport filters change.
    static func indexGames(_ games: [Game], favorites: Set<String> = []) {
        let items: [CSSearchableItem] = games.compactMap { game in
            guard let eventID = game.idEvent else { return nil }

            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = "\(game.strAwayTeam) at \(game.strHomeTeam)"

            // Build description with date and sport info
            var descParts: [String] = []
            if let date = game.standardDate {
                descParts.append(date.formatted(.dateTime.month().day().hour().minute()))
            }
            if let leagueStr = game.idLeague,
               let intLeague = Int(leagueStr),
               let league = Leagues(rawValue: intLeague) {
                let sport = SportType(league: league)
                descParts.append(sport.capitalized)
            }
            attributes.contentDescription = descParts.joined(separator: " • ")

            // Keywords for better search matching
            attributes.keywords = [
                game.strHomeTeam,
                game.strAwayTeam,
                game.strLeague ?? ""
            ].filter { !$0.isEmpty }

            // Boost favorites in ranking
            if favorites.contains(game.strHomeTeam) || favorites.contains(game.strAwayTeam) {
                attributes.rankingHint = NSNumber(value: 1)
            }

            return CSSearchableItem(
                uniqueIdentifier: "game-\(eventID)",
                domainIdentifier: domainGames,
                attributeSet: attributes
            )
        }

        // Index in batches to avoid overwhelming Spotlight
        let batchSize = 100
        for startIndex in stride(from: 0, to: items.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, items.count)
            let batch = Array(items[startIndex..<endIndex])
            CSSearchableIndex.default().indexSearchableItems(batch) { error in
                if let error {
                    AppLogger.general.error("Spotlight indexing failed: \(error.localizedDescription)")
                }
            }
        }

        AppLogger.general.info("Spotlight: indexed \(items.count) games")
    }

    /// Indexes favorite teams in CoreSpotlight.
    static func indexFavoriteTeams(_ teamNames: Set<String>) {
        // Delete old team entries first
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainTeams]) { _ in
            let items = teamNames.map { name -> CSSearchableItem in
                let attributes = CSSearchableItemAttributeSet(contentType: .content)
                attributes.title = name
                attributes.contentDescription = "Favorite team in SportsCal"
                attributes.keywords = [name]
                attributes.rankingHint = NSNumber(value: 2)

                return CSSearchableItem(
                    uniqueIdentifier: "team-\(name)",
                    domainIdentifier: domainTeams,
                    attributeSet: attributes
                )
            }

            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error {
                    AppLogger.general.error("Spotlight team indexing failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Removes all SportsCal items from the Spotlight index.
    static func deleteAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainGames, domainTeams]) { error in
            if let error {
                AppLogger.general.error("Spotlight delete failed: \(error.localizedDescription)")
            }
        }
    }
}
