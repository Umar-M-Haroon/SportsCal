//
//  SpotlightIndexer.swift
//  SportsCal
//
//  Indexes games and favorite teams in CoreSpotlight for system-wide search.
//

import CoreSpotlight
import SportsCalModel
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import os

enum SpotlightIndexer {
    private static let domainGames = "com.sportscal.games"
    private static let domainTeams = "com.sportscal.teams"
    private static let domainDates = "com.sportscal.dates"

    #if canImport(UIKit)
    private static var thumbnailCache: [SportType: Data] = [:]

    private static func thumbnail(for sport: SportType) -> Data? {
        if let cached = thumbnailCache[sport] { return cached }

        let size = CGSize(width: 60, height: 60)
        let renderer = UIGraphicsImageRenderer(size: size)
        let data = renderer.pngData { context in
            // Draw filled circle with sport color
            let uiColor = UIColor(sport.color)
            uiColor.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))

            // Draw SF Symbol centered in white
            let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
            if let symbol = UIImage(systemName: sport.systemImage, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                let symbolSize = symbol.size
                let origin = CGPoint(
                    x: (size.width - symbolSize.width) / 2,
                    y: (size.height - symbolSize.height) / 2
                )
                symbol.draw(at: origin)
            }
        }
        thumbnailCache[sport] = data
        return data
    }
    #endif

    /// Indexes upcoming games in CoreSpotlight.
    /// Call after schedule data refreshes or sport filters change.
    static func indexGames(_ games: [Game], favorites: Set<String> = []) {
        let items: [CSSearchableItem] = games.compactMap { game in
            guard let eventID = game.idEvent else { return nil }

            let attributes = CSSearchableItemAttributeSet(contentType: .content)

            // Use tournament/event name for individual sports
            if game.isIndividualSport {
                attributes.title = game.strHomeTeam
            } else {
                attributes.title = "\(game.strAwayTeam) at \(game.strHomeTeam)"
            }

            // Build description with date and sport info
            var descParts: [String] = []
            if let date = game.standardDate {
                descParts.append(date.formatted(.dateTime.month().day().hour().minute()))
            }

            var sport: SportType?
            if let leagueStr = game.idLeague,
               let intLeague = Int(leagueStr),
               let league = Leagues(rawValue: intLeague) {
                sport = SportType(league: league)
                descParts.append(sport!.capitalized)
            }

            // Add leaderboard info for individual sports
            if game.isRace {
                let leaders = game.raceLeaderboard.prefix(3)
                if !leaders.isEmpty {
                    let leaderStr = leaders.map { "\($0.name) P\($0.position)" }.joined(separator: ", ")
                    descParts.append(leaderStr)
                }
            } else if game.isIndividualSport {
                let leaders = game.leaderboard.prefix(3)
                if !leaders.isEmpty {
                    let leaderStr = leaders.map { "\($0.name) \($0.score)" }.joined(separator: ", ")
                    descParts.append("Leader: \(leaderStr)")
                }
            }

            attributes.contentDescription = descParts.joined(separator: " • ")

            // Keywords for better search matching
            var keywords = [
                game.strHomeTeam,
                game.strAwayTeam,
                game.strLeague ?? ""
            ].filter { !$0.isEmpty }

            if let sport {
                keywords.append(sport.displayName)
                keywords.append(sport.capitalized)
            }
            attributes.keywords = keywords

            // Boost favorites in ranking
            if favorites.contains(game.strHomeTeam) || favorites.contains(game.strAwayTeam) {
                attributes.rankingHint = NSNumber(value: 1)
            }

            #if canImport(UIKit)
            if let sport {
                attributes.thumbnailData = thumbnail(for: sport)
            }
            #endif

            return CSSearchableItem(
                uniqueIdentifier: "game-\(eventID)",
                domainIdentifier: domainGames,
                attributeSet: attributes
            )
        }

        // Index date-based items for the next 7 days
        let dateItems = buildDateItems(from: games)

        let allItems = items + dateItems

        // Index in batches to avoid overwhelming Spotlight
        let batchSize = 100
        for startIndex in stride(from: 0, to: allItems.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, allItems.count)
            let batch = Array(allItems[startIndex..<endIndex])
            CSSearchableIndex.default().indexSearchableItems(batch) { error in
                if let error {
                    AppLogger.general.error("Spotlight indexing failed: \(error.localizedDescription)")
                }
            }
        }

        AppLogger.general.info("Spotlight: indexed \(items.count) games, \(dateItems.count) date items")
    }

    /// Builds date-aggregated Spotlight items for the next 7 days.
    private static func buildDateItems(from games: [Game]) -> [CSSearchableItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekFromNow = calendar.date(byAdding: .day, value: 7, to: today) else { return [] }

        // Group games by date
        var gamesByDate: [Date: [Game]] = [:]
        for game in games {
            guard let gameDate = game.standardDate else { continue }
            let dayStart = calendar.startOfDay(for: gameDate)
            guard dayStart >= today && dayStart < weekFromNow else { continue }
            gamesByDate[dayStart, default: []].append(game)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMM d"
        let idFormatter = DateFormatter()
        idFormatter.dateFormat = "yyyy-MM-dd"

        return gamesByDate.compactMap { (date, dayGames) -> CSSearchableItem? in
            guard !dayGames.isEmpty else { return nil }

            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            let count = dayGames.count
            let formattedDate = dateFormatter.string(from: date)
            attributes.title = "\(count) \(count == 1 ? "game" : "games") on \(formattedDate)"

            // Sport breakdown
            var sportCounts: [SportType: Int] = [:]
            for game in dayGames {
                guard let leagueStr = game.idLeague,
                      let intLeague = Int(leagueStr),
                      let league = Leagues(rawValue: intLeague) else { continue }
                let sport = SportType(league: league)
                sportCounts[sport, default: 0] += 1
            }
            let breakdown = sportCounts
                .sorted { $0.value > $1.value }
                .map { "\($0.value) \($0.key.displayName)" }
                .joined(separator: ", ")
            attributes.contentDescription = breakdown

            // Keywords
            let dayName = DateFormatter().weekdaySymbols[calendar.component(.weekday, from: date) - 1]
            attributes.keywords = [dayName, formattedDate, "games", "schedule"]

            let dateID = idFormatter.string(from: date)
            return CSSearchableItem(
                uniqueIdentifier: "date-\(dateID)",
                domainIdentifier: domainDates,
                attributeSet: attributes
            )
        }
    }

    /// Indexes favorite teams in CoreSpotlight.
    static func indexFavoriteTeams(_ teamNames: Set<String>) {
        // Delete old team entries first
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainTeams]) { _ in
            let items = teamNames.map { name -> CSSearchableItem in
                let attributes = CSSearchableItemAttributeSet(contentType: .content)
                attributes.title = name
                attributes.contentDescription = "Favorite team in Scoreline"
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
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainGames, domainTeams, domainDates]) { error in
            if let error {
                AppLogger.general.error("Spotlight delete failed: \(error.localizedDescription)")
            }
        }
    }
}
