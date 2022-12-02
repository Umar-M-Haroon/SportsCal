//
//  Provider.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/30/22.
//

import Foundation
import WidgetKit
import SwiftUI
import Intents
import Combine
import SportsCalModel

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationIntent
    let game: [Game]?
    var images: [String: Data]?
    let teams: [Team]
}
class Provider: IntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        return SimpleEntry(date: Date(), configuration: ConfigurationIntent(), game: [Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: nil, strLeague: nil, idHomeTeam: nil, idAwayTeam: nil, strHomeTeam: "Denver Nuggets", strAwayTeam: "Milwaukee Bucks", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: nil, intAwayScore: nil, strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: nil, strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: DateFormatters.isoFormatter.string(from: .now))], images: nil, teams: [])
    }
    
    func getSnapshot(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        Task {
            let (games, teams) = await handleNetworking(favoriteOnly: configuration.favoritesOnly?.boolValue ?? false, type: configurationToString(configuration: configuration))
            if games.isEmpty {
                let entry = SimpleEntry(date: Date(), configuration: configuration, game: nil, images: nil, teams: teams)
                completion(entry)
                return
            }
            if games.count < 2 {
                var entry = SimpleEntry(date: Date(), configuration: configuration, game: [games[0]], images: nil, teams: teams)
                guard let homeTeam = Team.getTeamInfoFrom(teams: teams, teamID: games[0].idHomeTeam),
                      let awayTeam = Team.getTeamInfoFrom(teams: teams, teamID: games[0].idAwayTeam) else {
                    completion(entry)
                    return
                }
                if let images = try? await getImagesFor(homeTeam: homeTeam, awayTeam: awayTeam) {
                    entry.images = images
                }
                completion(entry)
                return
            }
            
            var allImages: [String: Data] = [:]
            for game in games {
                if let homeTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idHomeTeam), let awayTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idAwayTeam) {
                    async let images = getImagesFor(homeTeam: homeTeam, awayTeam: awayTeam)
                    try await allImages.merge(images, uniquingKeysWith: {$1})
                }
            }
            let entry = SimpleEntry(date: Date(), configuration: configuration, game: Array(games.prefix(through: 1)), images: allImages, teams: teams)
            completion(entry)
        }
    }
    
    func getImagesFor(homeTeam: Team, awayTeam: Team) async throws -> [String: Data] {
        guard let homeImageURL = homeTeam.strTeamBadge,
              let homeID = homeTeam.idTeam,
              let awayImageURL = awayTeam.strTeamBadge,
              let awayID = awayTeam.idTeam else {
            return [:]
        }
        let homeImage = try await NetworkHandler.getImageFor(url: homeImageURL, size: .tiny)
        let awayImage = try await NetworkHandler.getImageFor(url: awayImageURL, size: .tiny)
        return [homeID: homeImage, awayID: awayImage]
    }
    
    func getTimeline(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        Task {
            await completion(timelineHandler(configuration: configuration))
        }
    }
    
    func timelineHandler(configuration: ConfigurationIntent) async -> Timeline<Entry> {
        var entries: [SimpleEntry] = []
        let currentDate = Date()
        let (games, teams) = await handleNetworking(favoriteOnly: configuration.favoritesOnly?.boolValue ?? false, type: configurationToString(configuration: configuration))
        let entryDate = Calendar.current.date(byAdding: .minute, value: 3, to: currentDate)
        if games.isEmpty {
            let entry = SimpleEntry(date: entryDate!, configuration: configuration, game: nil, images: nil, teams: teams)
            //                let entry = SimpleEntry(date: entryDate!, configuration: configuration, game: [Game(idLeague: "4387", strHomeTeam: "uhoh", strAwayTeam: "Test")])
            entries.append(entry)
        } else if games.count < 2 {
            var entry = SimpleEntry(date: entryDate!, configuration: configuration, game: [games[0]], images: nil, teams: teams)
            guard let homeTeam = Team.getTeamInfoFrom(teams: teams, teamID: games[0].idHomeTeam),
                  let awayTeam = Team.getTeamInfoFrom(teams: teams, teamID: games[0].idAwayTeam) else {
                entries.append(entry)
                return Timeline(entries: entries, policy: .atEnd)
            }
            if let images = try? await getImagesFor(homeTeam: homeTeam, awayTeam: awayTeam) {
                entry.images = images
            }
            entries.append(entry)
        } else {
            let first2Games = games.prefix(through: 1)
            var allImages: [String: Data] = [:]
            for game in first2Games {
                if let homeTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idHomeTeam), let awayTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idAwayTeam) {
                    async let images = getImagesFor(homeTeam: homeTeam, awayTeam: awayTeam)
                    try? await allImages.merge(images, uniquingKeysWith: {$1})
                }
            }
            let entry = SimpleEntry(date: entryDate!, configuration: configuration, game: Array(first2Games), images: allImages, teams: teams)
            entries.append(entry)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
    
    func configurationToString(configuration: ConfigurationIntent) -> SportType {
        switch configuration.GameType {
        case .mLB:
            return .mlb
        case .nBA:
            return .basketball
        case .nHL:
            return .hockey
        case .nFL:
            return .nfl
        case .soccer:
            return .soccer
        case .unknown:
            return .hockey
        }
    }
    
    
    func handleNetworking(favoriteOnly: Bool, type: SportType) async -> ([Game], [Team])  {
        do {
            var games = try await NetworkHandler.getScheduleFor(sport: type).events
            games = games
                .filter({ game -> Bool in
                    guard let date = game.getDate(dateFormatter: DateFormatters.backupISOFormatter, isoFormatter: DateFormatters.isoFormatter) else { return false }
                    return date.timeIntervalSinceNow > 0
                })
            async let teams = NetworkHandler.getTeams()
            
            let favorites = Favorites()
            if favoriteOnly {
                games.removeAll { game in
                    !favorites.contains(game)
                }
            }
            return await (games, try teams)
        } catch let e {
            return ([Game(idLeague: "4387", strHomeTeam: "g", strAwayTeam: e.localizedDescription)], [])
        }
    }
}
